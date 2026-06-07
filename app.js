const STORAGE_KEY = "badminton-booking-tasks";

const courts = ["1号场地", "2号场地", "3号场地", "4号场地", "5号场地", "6号场地"];
const statusMap = {
  waiting: ["等待中", "status-waiting"],
  standby: ["待命中", "status-ready"],
  ready: ["刷新抢场中", "urgent"],
  paused: ["已暂停", "status-paused"],
  done: ["请去微信支付", "status-done"],
};

let tasks = loadTasks();
let soundEnabled = false;
let audioContext = null;

const form = document.querySelector("#taskForm");
const bookingDate = document.querySelector("#bookingDate");
const startTime = document.querySelector("#startTime");
const endTime = document.querySelector("#endTime");
const dateStrip = document.querySelector("#dateStrip");
const courtGrid = document.querySelector("#courtGrid");
const strategy = document.querySelector("#strategy");
const retryInterval = document.querySelector("#retryInterval");
const retryDuration = document.querySelector("#retryDuration");
const note = document.querySelector("#note");
const openTimePreview = document.querySelector("#openTimePreview");
const taskList = document.querySelector("#taskList");
const logList = document.querySelector("#logList");

init();

function init() {
  renderTimeOptions();
  renderCourts();
  setDefaultDate();
  renderDateStrip();
  bindEvents();
  renderTasks();
  updateClock();
  addLog("系统已就绪，可以创建预约任务。");
  setInterval(tick, 1000);
}

function bindEvents() {
  bookingDate.addEventListener("change", () => {
    updateOpenTimePreview();
    renderDateStrip();
  });
  startTime.addEventListener("change", syncEndTime);
  form.addEventListener("submit", addTask);
  document.querySelector("#clearLog").addEventListener("click", () => {
    logList.innerHTML = "";
    addLog("日志已清空。");
  });
  document.querySelector("#clearDone").addEventListener("click", () => {
    tasks = tasks.filter((task) => task.status !== "done");
    saveTasks();
    renderTasks();
    addLog("已清理待支付任务。");
  });
  document.querySelector("#enableSound").addEventListener("click", enableSound);
  dateStrip.addEventListener("click", (event) => {
    const button = event.target.closest(".date-chip");
    if (!button || button.disabled) {
      return;
    }
    bookingDate.value = button.dataset.date;
    updateOpenTimePreview();
    renderDateStrip();
    const releaseText = button.classList.contains("future-release") ? "待放号，已设为 24 点守候目标。" : "已放号，可立即预约。";
    addLog(`已选择 ${button.dataset.date}，${releaseText}`);
  });
}

function renderTimeOptions() {
  for (let hour = 8; hour <= 21; hour += 1) {
    const value = `${String(hour).padStart(2, "0")}:00`;
    startTime.append(new Option(value, value));
  }
  startTime.value = "10:00";
  syncEndTime();
}

function syncEndTime() {
  endTime.innerHTML = "";
  const startHour = Number(startTime.value.slice(0, 2));
  for (let hour = startHour + 1; hour <= 22; hour += 1) {
    const value = `${String(hour).padStart(2, "0")}:00`;
    endTime.append(new Option(value, value));
  }
}

function renderCourts() {
  courtGrid.innerHTML = courts
    .map(
      (court, index) => `
        <label class="court-option">
          <input type="checkbox" value="${court}" ${index >= 2 && index <= 4 ? "checked" : ""} />
          <span>${court}</span>
        </label>
      `,
    )
    .join("");
}

function setDefaultDate() {
  const latestBookableDate = new Date();
  latestBookableDate.setDate(latestBookableDate.getDate() + 6);
  bookingDate.min = toDateInput(addDays(new Date(), 1));
  bookingDate.removeAttribute("max");
  bookingDate.value = toDateInput(latestBookableDate);
  updateOpenTimePreview();
}

function renderDateStrip() {
  const today = startOfDay(new Date());
  const minBookable = addDays(today, 1);
  const maxBookable = addDays(today, 6);
  const selected = bookingDate.value;

  dateStrip.innerHTML = Array.from({ length: 14 }, (_, index) => {
    const date = addDays(today, index);
    const value = toDateInput(date);
    const pastOrToday = date <= today;
    const released = date >= minBookable && date <= maxBookable;
    const futureRelease = date > maxBookable;
    const active = value === selected;
    return `
      <button
        class="date-chip ${released ? "available" : ""} ${futureRelease ? "future-release" : ""} ${pastOrToday ? "disabled" : ""} ${active ? "active" : ""}"
        type="button"
        data-date="${value}"
        ${pastOrToday ? "disabled" : ""}
      >
        <strong>${date.toLocaleDateString("zh-CN", { weekday: "short" })}</strong>
        <span>${pad(date.getMonth() + 1)}/${pad(date.getDate())}</span>
        <small>${active ? "已选中" : released ? "已放号" : futureRelease ? "待放号" : "不可约"}</small>
      </button>
    `;
  }).join("");

}

function addTask(event) {
  event.preventDefault();
  if (new Date(`${bookingDate.value}T00:00:00`) <= startOfDay(new Date())) {
    addLog("不能预约今天或过去日期，请选择未来日期。");
    return;
  }
  const selectedCourts = [...courtGrid.querySelectorAll("input:checked")].map((input) => input.value);
  if (!selectedCourts.length) {
    addLog("请至少选择一个场地偏好。");
    return;
  }

  const task = {
    id: crypto.randomUUID(),
    date: bookingDate.value,
    start: startTime.value,
    end: endTime.value,
    courts: selectedCourts,
    strategy: strategy.value,
    retryInterval: Number(retryInterval.value),
    retryDuration: Number(retryDuration.value),
    retryCount: 0,
    lastRetryAt: null,
    rushStartedAt: null,
    note: note.value.trim(),
    openAt: getOpenDate(bookingDate.value).toISOString(),
    status: "waiting",
    createdAt: new Date().toISOString(),
  };

  if (new Date(task.openAt).getTime() <= Date.now()) {
    task.status = "ready";
    task.rushStartedAt = new Date().toISOString();
  }

  tasks.unshift(task);
  saveTasks();
  renderTasks();
  if (task.status === "ready") {
    addLog(`已添加 ${formatDate(task.date)} ${task.start}-${task.end}，当前已放号，立即发起预约。`);
  } else {
    addLog(`已添加 ${formatDate(task.date)} ${task.start}-${task.end} 的预约任务。`);
  }
  note.value = "";
}

function tick() {
  updateClock();
  let changed = false;
  const now = Date.now();

  tasks = tasks.map((task) => {
    const openTime = new Date(task.openAt).getTime();
    if (task.status === "waiting" && openTime - now <= 30 * 1000 && openTime > now) {
      changed = true;
      addLog(`${formatDate(task.date)} ${task.start}-${task.end} 进入 30 秒待命，请保持小程序和网络就绪。`);
      return { ...task, status: "standby" };
    }
    if ((task.status === "waiting" || task.status === "standby") && openTime <= now) {
      changed = true;
      addLog(`${formatDate(task.date)} ${task.start}-${task.end} 已到 00:00:00，进入持续刷新抢场。`);
      return { ...task, status: "ready", retryCount: 0, lastRetryAt: null, rushStartedAt: new Date(now).toISOString() };
    }
    if (task.status === "ready") {
      const interval = task.retryInterval || 500;
      const lastRetryAt = task.lastRetryAt ? new Date(task.lastRetryAt).getTime() : 0;
      const rushStartedAt = task.rushStartedAt ? new Date(task.rushStartedAt).getTime() : openTime;
      const retryDuration = (task.retryDuration || 180) * 1000;
      if (now - rushStartedAt > retryDuration) {
        changed = true;
        addLog(`${formatDate(task.date)} ${task.start}-${task.end} 已达到最大重试时长，自动暂停抢场。`);
        return { ...task, status: "paused" };
      }
      if (now - lastRetryAt >= interval) {
        const retryCount = (task.retryCount || 0) + 1;
        changed = true;
        if (retryCount <= 5 || retryCount % 20 === 0) {
          addLog(`${formatDate(task.date)} ${task.start}-${task.end} 第 ${retryCount} 次发起抢场，失败则继续重试。`);
        }
        return { ...task, retryCount, lastRetryAt: new Date(now).toISOString() };
      }
    }
    return task;
  });

  if (changed) {
    saveTasks();
    renderTasks();
    beep(3);
  } else {
    updateCountdowns();
  }
}

function updateClock() {
  const now = new Date();
  document.querySelector("#nowText").textContent = now.toLocaleTimeString("zh-CN", { hour12: false });
  document.querySelector("#dateText").textContent = now.toLocaleDateString("zh-CN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    weekday: "long",
  });
}

function updateOpenTimePreview() {
  if (!bookingDate.value) {
    openTimePreview.textContent = "请选择日期";
    return;
  }
  openTimePreview.textContent = formatDateTime(getOpenDate(bookingDate.value));
}

function renderTasks() {
  if (!tasks.length) {
    taskList.innerHTML = `<div class="empty">还没有任务，先创建一个目标场次。</div>`;
    return;
  }

  taskList.innerHTML = tasks.map(renderTaskCard).join("");
  taskList.querySelectorAll("[data-action]").forEach((button) => {
    button.addEventListener("click", handleTaskAction);
  });
  updateCountdowns();
}

function renderTaskCard(task) {
  const [label, className] = statusMap[task.status] || statusMap.waiting;
  const strategyLabel = {
    "same-first": "连续两小时，优先同场",
    "mixed-ok": "连续两小时，可跨场",
    continuous: "连续两小时，优先同场",
    adjacent: "连续两小时，可跨场",
  }[task.strategy];

  return `
    <article class="task-card" data-task-id="${task.id}">
      <div class="task-top">
        <div class="task-title">${formatDate(task.date)} ${task.start}-${task.end}</div>
        <span class="status ${className}">${label}</span>
      </div>
      <div class="task-meta">
        <span>偏好：${task.courts.join("、")}</span>
        <span>策略：${strategyLabel}</span>
        <span>刷新：${(task.retryInterval || 500) / 1000} 秒/次</span>
        <span>重试：${Math.round((task.retryDuration || 180) / 60)} 分钟</span>
        <span>开放：${formatDateTime(new Date(task.openAt))}</span>
      </div>
      <div class="task-meta">
        <span class="countdown" data-countdown="${task.id}">计算中</span>
        ${task.note ? `<span>备注：${escapeHtml(task.note)}</span>` : ""}
      </div>
      <div class="task-actions">
        <button type="button" data-action="toggle" data-id="${task.id}">
          ${task.status === "paused" ? "恢复" : "暂停"}
        </button>
        <button type="button" data-action="done" data-id="${task.id}">系统已抢票成功，请去微信支付</button>
        <button type="button" data-action="delete" data-id="${task.id}">删除</button>
      </div>
    </article>
  `;
}

function handleTaskAction(event) {
  const { action, id } = event.currentTarget.dataset;
  const task = tasks.find((item) => item.id === id);
  if (!task) return;

  if (action === "delete") {
    tasks = tasks.filter((item) => item.id !== id);
    addLog(`已删除 ${formatDate(task.date)} ${task.start}-${task.end} 的任务。`);
  }

  if (action === "toggle") {
    task.status = task.status === "paused" ? "waiting" : "paused";
    addLog(`${formatDate(task.date)} ${task.start}-${task.end} 已${task.status === "paused" ? "暂停" : "恢复"}。`);
  }

  if (action === "done") {
    task.status = "done";
    addLog(`${formatDate(task.date)} ${task.start}-${task.end} 系统已抢票成功，请去微信支付。`);
  }

  saveTasks();
  renderTasks();
}

function updateCountdowns() {
  tasks.forEach((task) => {
    const node = taskList.querySelector(`[data-countdown="${task.id}"]`);
    if (!node) return;
    if (task.status === "paused") {
      node.textContent = "任务已暂停";
      return;
    }
    if (task.status === "done") {
      node.textContent = "系统已抢票成功，请去微信支付";
      return;
    }
    if (task.status === "ready") {
      node.textContent = `持续发起抢场中，已尝试 ${task.retryCount || 0} 次，失败会继续重试`;
      return;
    }
    const diff = new Date(task.openAt).getTime() - Date.now();
    if (diff <= 0) {
      node.textContent = "已到 00:00:00，请立即抢场";
      return;
    }
    node.textContent = `距离 00:00 放号 ${formatDuration(diff)}`;
  });
}

function getOpenDate(dateValue) {
  const date = new Date(`${dateValue}T00:00:00`);
  date.setDate(date.getDate() - 6);
  return date;
}

function addDays(date, days) {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return startOfDay(next);
}

function startOfDay(date) {
  const next = new Date(date);
  next.setHours(0, 0, 0, 0);
  return next;
}

function formatDuration(ms) {
  const total = Math.floor(ms / 1000);
  const days = Math.floor(total / 86400);
  const hours = Math.floor((total % 86400) / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = total % 60;
  return `${days}天 ${pad(hours)}:${pad(minutes)}:${pad(seconds)}`;
}

function formatDate(dateValue) {
  return new Date(`${dateValue}T00:00:00`).toLocaleDateString("zh-CN", {
    month: "2-digit",
    day: "2-digit",
    weekday: "short",
  });
}

function formatDateTime(date) {
  return date.toLocaleString("zh-CN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });
}

function toDateInput(date) {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function pad(value) {
  return String(value).padStart(2, "0");
}

function addLog(message) {
  const item = document.createElement("li");
  const time = new Date().toLocaleTimeString("zh-CN", { hour12: false });
  item.innerHTML = `<strong>${time}</strong><span>${escapeHtml(message)}</span>`;
  logList.prepend(item);
}

function enableSound() {
  const AudioContext = window.AudioContext || window.webkitAudioContext;
  if (!AudioContext) {
    addLog("当前浏览器不支持声音提醒。");
    return;
  }
  audioContext = audioContext || new AudioContext();
  soundEnabled = true;
  document.querySelector("#enableSound").classList.add("enabled");
  document.querySelector("#enableSound").textContent = "声音提醒已开启";
  addLog("声音提醒已开启，30 秒待命和 00:00 抢场时会响铃。");
  beep(1);
}

function beep(times = 1) {
  if (!soundEnabled || !audioContext) return;
  for (let index = 0; index < times; index += 1) {
    const start = audioContext.currentTime + index * 0.22;
    const oscillator = audioContext.createOscillator();
    const gain = audioContext.createGain();
    oscillator.connect(gain);
    gain.connect(audioContext.destination);
    oscillator.frequency.value = 880;
    gain.gain.setValueAtTime(0.08, start);
    gain.gain.exponentialRampToValueAtTime(0.001, start + 0.16);
    oscillator.start(start);
    oscillator.stop(start + 0.18);
  }
}

function saveTasks() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(tasks));
}

function loadTasks() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
  } catch {
    return [];
  }
}

function escapeHtml(value) {
  return value.replace(/[&<>"']/g, (char) => {
    return {
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#039;",
    }[char];
  });
}
