#!/bin/bash

# ----- Configuración -----
APP_NAME="ThreadMemoryDemo"
INTERVAL=2                 # segundos entre muestras
OUT_DIR="monitor-report"
DATA_FILE="$OUT_DIR/metrics.csv"
EVENTS_NDJSON="$OUT_DIR/events.ndjson"
REPORT_FILE="$OUT_DIR/report.html"
VIRTUAL_THREAD_COUNT_FILE="virtual_threads.state"

mkdir -p "$OUT_DIR"

# ----- Localiza PID -----
PID=$(jps 2>/dev/null | grep "$APP_NAME" | awk '{print $1}' | head -1)
if [ -z "$PID" ]; then
  echo "❌ $APP_NAME no está ejecutándose. Lanza primero ./run-demo.sh"
  exit 1
fi

# ----- Helpers -----
ms_now() { echo $(( $(date +%s) * 1000 )); }
num_or_zero() { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo "0"; }

add_event() {
  local type="$1"; shift
  local desc="$*"
  local ts=$(ms_now)
  # Escapar comillas en descripción
  desc=$(echo "$desc" | sed 's/"/\\"/g')
  echo "{\"timestamp\": $ts, \"type\": \"$type\", \"description\": \"$desc\"}" >> "$EVENTS_NDJSON"
}

parse_pair() {
  local line="$1"
  if [[ "$line" =~ reserved=([0-9]+)KB.*committed=([0-9]+)KB ]]; then
    echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
  else
    echo "0 0"
  fi
}

parse_stack_triplet() {
  local line="$1"
  local res=0 com=0 peak=0
  [[ "$line" =~ reserved=([0-9]+)KB ]] && res="${BASH_REMATCH[1]}"
  [[ "$line" =~ committed=([0-9]+)KB ]] && com="${BASH_REMATCH[1]}"
  [[ "$line" =~ peak=([0-9]+)KB ]] && peak="${BASH_REMATCH[1]}"
  echo "$res $com $peak"
}

to_mb() {
  local kb=$(num_or_zero "$1")
  echo $(( kb / 1024 ))
}

# Obtiene el RSS en KB (Resident Set Size - Memoria Física Real usada)
# ps -o rss= -p $PID devuelve el RSS en KiloBytes en la mayoría de los sistemas Linux.
get_rss_kb() {
  local rss_kb=$(ps -o rss= -p "$PID" 2>/dev/null | awk '{print $1}')
  echo $(num_or_zero "$rss_kb")
}

# ----- Inicializa archivos (INCLUYENDO RSS) -----
echo "timestamp,totalThreads,platformThreads,virtualThreads,javaHeapReservedMB,javaHeapCommittedMB,nativeReservedMB,nativeCommittedMB,threadReservedMB,threadCommittedMB,stackReservedMB,stackCommittedMB,stackPeakMB,processRSSMB" > "$DATA_FILE"
: > "$EVENTS_NDJSON"

echo "✓ Monitorizando $APP_NAME (PID=$PID)"
add_event "start" "Monitor iniciado para PID=$PID"

PREV_PLATFORM=0
PREV_VIRTUAL=0
FIRST_PLATFORM_FIRED=0
FIRST_VIRTUAL_FIRED=0

# ----- Finalización: genera report.html -----
finalize_report() {
  local EVENTS_JSON="[]"
  if [ -s "$EVENTS_NDJSON" ]; then
    EVENTS_JSON=$(awk 'BEGIN{print "["} { if(NR>1) printf(","); printf("%s",$0) } END{print "]"}' "$EVENTS_NDJSON")
  fi

  local CSV_CONTENT
  CSV_CONTENT=$(sed 's/`/\\`/g' "$DATA_FILE")

  cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>Reporte de Monitoreo JVM</title>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns@3.0.0/dist/chartjs-adapter-date-fns.bundle.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/chartjs-plugin-annotation@3.0.1/dist/chartjs-plugin-annotation.min.js"></script>
<style>
  :root {
    --bg: #0b0e14;
    --card: #12161c;
    --text: #e6e8ef;
    --muted: #9aa4b2;
    --edge: #1c222b;
    --accent: #8ab4ff;
    --chart-bg: #0b0e14;
    --tick-color: #a7b4c7;
  }
  /* Modo Claro */
  .light-mode {
    --bg: #f0f2f5;
    --card: #ffffff;
    --text: #1e293b;
    --muted: #64748b;
    --edge: #e2e8f0;
    --accent: #2563eb;
    --chart-bg: #ffffff;
    --tick-color: #64748b;
  }

  body { font-family: -apple-system, Segoe UI, Roboto, sans-serif; background: var(--bg); color: var(--text); margin:0; transition: background 0.3s, color 0.3s; }

  .header {
    padding: 18px; background: var(--card); border-bottom: 1px solid var(--edge);
    display: flex; justify-content: space-between; align-items: center;
  }
  .header h1 { margin:0; font-size:18px; font-weight:600; color: var(--text); }
  .meta { font-size:12px; color:var(--muted); margin-top:6px; }

  button.theme-toggle {
    background: var(--edge); border: none; color: var(--text); padding: 8px 12px;
    border-radius: 6px; cursor: pointer; font-size: 14px; transition: background 0.2s;
  }
  button.theme-toggle:hover { background: var(--accent); color: white; }

  .wrap { max-width: 1280px; margin: 18px auto 40px; padding: 0 16px; }
  .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(240px,1fr)); gap:12px; margin-bottom:16px; }
  .card { background: var(--card); border:1px solid var(--edge); border-radius:10px; padding:14px; transition: background 0.3s; }
  .label { font-size:11px; color:var(--muted); text-transform:uppercase; letter-spacing:.6px; }
  .kpi { font-size:24px; font-weight:700; color: var(--accent); margin-top:4px; }

  .chart { background: var(--card); border:1px solid var(--edge); border-radius:10px; padding:14px; margin-bottom:14px; transition: background 0.3s; }
  .chart h3 { margin:0 0 10px; font-size:13px; color:var(--text); font-weight:600; letter-spacing:.3px; }

  .events { background: var(--card); border:1px solid var(--edge); border-radius:10px; padding:14px; transition: background 0.3s; }
  .event { border-left:3px solid #4f7cff; padding:8px 10px; margin:6px 0; background: var(--bg); border-radius: 0 4px 4px 0; }
  .event small { color:var(--muted); }

  .explanation {
    margin-top: 30px;
    padding: 20px;
    background: #1c222b;
    border: 1px solid #4f7cff;
    border-radius: 10px;
    color: #e6e8ef;
    transition: background 0.3s;
  }
  .light-mode .explanation {
    background: #e0f2fe;
    color: #1e293b;
    border: 1px solid #38bdf8;
  }
  .explanation h3 { margin-top: 0; color: #8ab4ff; }
  .light-mode .explanation h3 { color: #2563eb; }

  canvas { border-radius:6px; }
</style>
</head>
<body>
  <div class="header">
    <div>
      <h1>Reporte de Monitoreo JVM — $APP_NAME (PID $PID)</h1>
      <div class="meta">Generado: <span id="genDate"></span></div>
    </div>
    <button class="theme-toggle" onclick="toggleTheme()">🌗 Tema</button>
  </div>

  <div class="wrap">
    <div class="grid" id="kpis">
          <div class="card"><div class="label">Platform Threads</div><div class="kpi" id="kpiPlatform">-</div></div>
          <div class="card"><div class="label">Virtual Threads</div><div class="kpi" id="kpiVirtual">-</div></div>
          <div class="card"><div class="label">Total Threads</div><div class="kpi" id="kpiTotal">-</div></div>
          <div class="card"><div class="label">**RSS (RAM FÍSICA)**</div><div class="kpi" id="kpiRSS">-</div></div>
          <div class="card"><div class="label">Heap (reserved / committed)</div><div class="kpi" id="kpiHeap">-</div></div>
          <div class="card"><div class="label">Native Total (reserved / committed)</div><div class="kpi" id="kpiNative">-</div></div>
          <div class="card"><div class="label">Thread (reserved / committed)</div><div class="kpi" id="kpiThread">-</div></div>
          <div class="card"><div class="label">Thread Stack (reserved / committed / peak)</div><div class="kpi" id="kpiStack">-</div></div>
        </div>

    <div class="chart"><h3>🧵 Hilos (Platform / Virtual / Total)</h3><canvas id="threadsChart"></canvas></div>
    <div class="chart"><h3>💾 Memoria (MB)</h3><canvas id="memoryChart"></canvas></div>

    <div class="events">
      <h3>📌 Eventos detectados</h3>
      <div id="eventsList"></div>
    </div>

    <div class="explanation">
      <h3>💡 Aclaración sobre Memoria Virtual vs. Física (RAM)</h3>
      <p>La diferencia entre la memoria "Reservada" (Virtual) y el **RSS** (Física) es fundamental en esta demo:</p>

      <h4>💾 El problema de los Platform Threads (Hilos Tradicionales)</h4>
      <p>Cuando la demo crea 500 **Platform Threads**, el sistema operativo está obligado a <strong>reservar (comprometer)</strong> un gran bloque de espacio de direcciones virtuales para la pila nativa de cada hilo (típicamente 1MB, 2MB o 4MB).</p>
      <ul>
        <li><strong>Memoria Virtual (Reservada):</strong> Si la reserva es de 2 MB/hilo, la suma total es de <strong>1 GB</strong> (500 hilos x 2 MB). Este valor lo ves reflejado en el gráfico como <strong>Thread Stack Reserved</strong>.</li>
        <li><strong>Memoria Física (RSS/Committed):</strong> Sin embargo, el sistema usa "asignación perezosa" (*lazy allocation*). La **RAM real (RSS)** solo se consume cuando el hilo escribe activamente en su pila. Como los 500 hilos de la demo están "durmiendo" (<code>Thread.sleep()</code>), su pila se mantiene muy pequeña (unos pocos KB), lo que resulta en un **RSS** total mucho menor que el giga reservado.</li>
      </ul>

      <h4>🚀 La solución con Virtual Threads (Hilos Ligeros)</h4>
      <p>Los **Virtual Threads** gestionan su pila fuera del espacio nativo reservado (en el Heap Java), y usan pilas extremadamente pequeñas. Por lo tanto, el valor de <strong>Thread Stack Reserved</strong> y el <strong>RSS</strong> apenas se mueven al crear miles de ellos, demostrando una eficiencia de memoria muy superior para tareas de I/O bloqueante.</p>
    </div>

  </div>

<script>
const CSV_DATA = \`
$CSV_CONTENT
\`;
const EVENTS = $EVENTS_JSON;

document.getElementById('genDate').textContent = new Date().toLocaleString();

// Plugin para pintar fondo del gráfico dinámicamente
const chartBg = {
  id: 'chartBg',
  beforeDraw(chart, args, opts) {
    const {ctx, chartArea} = chart;
    if (!chartArea) return;
    ctx.save();
    // Usar color del CSS Variable
    ctx.fillStyle = opts.color || getComputedStyle(document.body).getPropertyValue('--chart-bg').trim();
    ctx.fillRect(chartArea.left, chartArea.top, chartArea.right-chartArea.left, chartArea.bottom-chartArea.top);
    ctx.restore();
  }
};
Chart.register(chartBg);
Chart.register(window['chartjs-plugin-annotation']);

function parseCsv(text) {
  const lines = text.trim().split('\\n');
  const header = lines.shift().split(',');
  return lines.map(l => {
    const cols = l.split(',');
    const row = {};
    header.forEach((h,i) => row[h] = cols[i]);
    row.timestamp = Number(row.timestamp);
    [
      'totalThreads','platformThreads','virtualThreads',
      'javaHeapReservedMB','javaHeapCommittedMB',
      'nativeReservedMB','nativeCommittedMB',
      'threadReservedMB','threadCommittedMB',
      'stackReservedMB','stackCommittedMB','stackPeakMB',
      'processRSSMB' // Nuevo campo RSS
    ].forEach(k => row[k] = Number(row[k]||0));
    return row;
  });
}

const data = parseCsv(CSV_DATA);
let tchart, mchart;

if (data.length === 0) {
  document.body.innerHTML += "<div style='padding:20px'>Sin datos</div>";
} else {
  const last = data[data.length-1];

  // KPIs
  document.getElementById('kpiPlatform').textContent = last.platformThreads;
  document.getElementById('kpiVirtual').textContent = last.virtualThreads;
  document.getElementById('kpiTotal').textContent = last.totalThreads;
  document.getElementById('kpiRSS').textContent = \`\${last.processRSSMB} MB\`; // Nuevo KPI RSS
  document.getElementById('kpiHeap').textContent   = \`\${last.javaHeapReservedMB} / \${last.javaHeapCommittedMB} MB\`;
  document.getElementById('kpiNative').textContent = \`\${last.nativeReservedMB} / \${last.nativeCommittedMB} MB\`;
  document.getElementById('kpiThread').textContent = \`\${last.threadReservedMB} / \${last.threadCommittedMB} MB\`;
  document.getElementById('kpiStack').textContent  = \`\${last.stackReservedMB} / \${last.stackCommittedMB} / \${last.stackPeakMB} MB\`;

  const commonOptions = {
    responsive: true,
    scales: {
      x: { type:'time', time:{ unit:'second' }, ticks:{ color: '#a7b4c7' }, grid: { color: 'rgba(128,128,128,0.1)' } },
      y: { beginAtZero:true, ticks:{ color: '#a7b4c7' }, grid: { color: 'rgba(128,128,128,0.1)' } }
    },
    plugins: {
      chartBg: {}, // Se usa el valor por defecto del plugin que lee CSS var
      legend: { labels:{ color: getComputedStyle(document.body).getPropertyValue('--text').trim() } },
      annotation: { annotations:{} }
    }
  };

  // Threads Chart
  tchart = new Chart(document.getElementById('threadsChart'), {
    type: 'line',
    data: {
      datasets: [
        { label:'Platform Threads', data: data.map(d=>({x:d.timestamp,y:d.platformThreads})), borderColor:'#f59e0b', backgroundColor:'rgba(245,158,11,.12)', tension:.25 },
        { label:'Virtual Threads',  data: data.map(d=>({x:d.timestamp,y:d.virtualThreads})),  borderColor:'#3b82f6', backgroundColor:'rgba(59,130,246,.12)',  tension:.25 },
        { label:'Total Threads',    data: data.map(d=>({x:d.timestamp,y:d.totalThreads})),    borderColor:'#9aa4b2', backgroundColor:'rgba(154,164,178,.10)', tension:.15, borderDash:[6,4] }
      ]
    },
    options: JSON.parse(JSON.stringify(commonOptions))
  });

  // Memory Chart (INCLUYENDO RSS)
  mchart = new Chart(document.getElementById('memoryChart'), {
    type: 'line',
    data: {
      datasets: [
        // RSS (Memoria Física REAL)
        { label:'Process RSS (RAM Física)', data: data.map(d=>({x:d.timestamp,y:d.processRSSMB})), borderColor:'#FF0000', backgroundColor:'rgba(255,0,0,.15)', tension:.1, borderWidth: 3 },
        // Heap
        { label:'Heap Reserved',       data: data.map(d=>({x:d.timestamp,y:d.javaHeapReservedMB})), borderColor:'#008000', backgroundColor:'rgba(0,128,0,.12)', tension:.2 },
        { label:'Heap Committed',      data: data.map(d=>({x:d.timestamp,y:d.javaHeapCommittedMB})), borderColor:'#32CD32', backgroundColor:'rgba(50,205,50,.12)',  tension:.2 },
        // Native
        { label:'Native Reserved',     data: data.map(d=>({x:d.timestamp,y:d.nativeReservedMB})),    borderColor:'#5A189A', backgroundColor:'rgba(90,24,154,.12)', tension:.2 },
        { label:'Native Committed',    data: data.map(d=>({x:d.timestamp,y:d.nativeCommittedMB})),   borderColor:'#9D4EDD', backgroundColor:'rgba(157,78,221,.12)', tension:.2 },
        // Stacks
        { label:'Thread Stack Reserved',data: data.map(d=>({x:d.timestamp,y:d.stackReservedMB})),    borderColor:'#FF6500', backgroundColor:'rgba(255,101,0,.10)', tension:.2 },
        { label:'Thread Stack Committed',data:data.map(d=>({x:d.timestamp,y:d.stackCommittedMB})),   borderColor:'#FFC300', backgroundColor:'rgba(255,195,0,.10)', tension:.2 }
      ]
    },
    options: JSON.parse(JSON.stringify(commonOptions))
  });

  // Eventos
  const eventsList = document.getElementById('eventsList');
  const ann = {};
  let collisionCounter = 0;

  EVENTS.sort((a, b) => a.timestamp - b.timestamp).forEach((e, idx) => {
    const d = new Date(e.timestamp);
    const el = document.createElement('div');
    el.className = 'event';
    el.innerHTML = '<b>'+d.toLocaleTimeString()+'</b> — '+ e.description + ' <small>['+e.type+']</small>';
    eventsList.appendChild(el);

    if (idx > 0 && e.timestamp - EVENTS[idx-1].timestamp < 3000) collisionCounter++; else collisionCounter = 0;
    let yAdj = (collisionCounter % 2 !== 0) ? -20 : 0;

    ann['e'+idx] = {
      type:'line', xMin:e.timestamp, xMax:e.timestamp,
      borderColor:'#4f7cff', borderDash:[5,5], borderWidth:1,
      label:{ display:true, content:e.description.split('(')[0].trim(), backgroundColor:'#4f7cff', color:'#fff', position: 'end', yAdjust: yAdj }
    };
  });
  tchart.options.plugins.annotation.annotations = ann;
  mchart.options.plugins.annotation.annotations = ann;
  tchart.update(); mchart.update();
}

// Función para cambiar tema y actualizar gráficos
function toggleTheme() {
  document.body.classList.toggle('light-mode');
  const isLight = document.body.classList.contains('light-mode');
  const tickColor = isLight ? '#64748b' : '#a7b4c7';

  [tchart, mchart].forEach(chart => {
    if(chart) {
      chart.options.scales.x.ticks.color = tickColor;
      chart.options.scales.y.ticks.color = tickColor;
      // Forzar repintado para que el plugin chartBg lea la nueva variable CSS
      chart.update();
    }
  });
}
</script>
</body>
</html>
EOF

  echo ""
  echo "✅ Reporte generado: $REPORT_FILE"
  echo "   Ábrelo directamente (file://) o con: python3 -m http.server 8000"
}

trap 'add_event "end" "Monitor finalizado"; finalize_report' EXIT

# ----- Bucle principal -----
while kill -0 "$PID" 2>/dev/null; do
  TS=$(ms_now)

  # Threads logic
  TDUMP=$(jcmd $PID Thread.print 2>/dev/null)
  TOTAL_THREADS_JCMD=$(echo "$TDUMP" | grep -c "java.lang.Thread.State")
  VIRTUAL_THREADS_STATE=$(cat "$VIRTUAL_THREAD_COUNT_FILE" 2>/dev/null)
  VIRTUAL_THREADS_STATE=${VIRTUAL_THREADS_STATE:-0}

  PLATFORM_THREADS_CHART=$TOTAL_THREADS_JCMD
  VIRTUAL_THREADS_CHART=$VIRTUAL_THREADS_STATE
  TOTAL_THREADS_CHART=$(( PLATFORM_THREADS_CHART + VIRTUAL_THREADS_CHART ))

  # NMT summary
  NMT=$(jcmd $PID VM.native_memory summary 2>/dev/null)
  TOTAL_LINE=$(echo "$NMT" | grep -E "^Total:")
  read TOTAL_RES_KB TOTAL_COM_KB <<< $(parse_pair "$TOTAL_LINE")
  JHEAP_LINE=$(echo "$NMT" | grep -E "^\s*-\s*Java Heap ")
  read JH_RES_KB JH_COM_KB <<< $(parse_pair "$JHEAP_LINE")
  THREAD_LINE=$(echo "$NMT" | grep -E "^\s*-\s*Thread ")
  read TH_RES_KB TH_COM_KB <<< $(parse_pair "$THREAD_LINE")
  STACK_LINE=$(echo "$NMT" | grep -E "stack:")
  read ST_RES_KB ST_COM_KB ST_PEAK_KB <<< $(parse_stack_triplet "$STACK_LINE")

  # RSS Metric
  RSS_KB=$(get_rss_kb)
  RSS_MB=$(to_mb "$RSS_KB")

  NAT_RES_MB=$(to_mb "$TOTAL_RES_KB")
  NAT_COM_MB=$(to_mb "$TOTAL_COM_KB")
  JH_RES_MB=$(to_mb "$JH_RES_KB")
  JH_COM_MB=$(to_mb "$JH_COM_KB")
  TH_RES_MB=$(to_mb "$TH_RES_KB")
  TH_COM_MB=$(to_mb "$TH_COM_KB")
  ST_RES_MB=$(to_mb "$ST_RES_KB")
  ST_COM_MB=$(to_mb "$ST_COM_KB")
  ST_PEAK_MB=$(to_mb "$ST_PEAK_KB")

  # Guarda CSV (Añadiendo RSS)
  echo "$TS,$TOTAL_THREADS_CHART,$PLATFORM_THREADS_CHART,$VIRTUAL_THREADS_CHART,$JH_RES_MB,$JH_COM_MB,$NAT_RES_MB,$NAT_COM_MB,$TH_RES_MB,$TH_COM_MB,$ST_RES_MB,$ST_COM_MB,$ST_PEAK_MB,$RSS_MB" >> "$DATA_FILE"

  # Eventos
  if [ $FIRST_PLATFORM_FIRED -eq 0 ] && [ $PLATFORM_THREADS_CHART -gt 15 ] && [ "$VIRTUAL_THREADS_CHART" -eq 0 ]; then
    add_event "platform_start" "Detectados hilos de plataforma (demo): $PLATFORM_THREADS_CHART"
    FIRST_PLATFORM_FIRED=1
  fi
  if [ $FIRST_VIRTUAL_FIRED -eq 0 ] && [ $VIRTUAL_THREADS_CHART -gt 0 ]; then
    add_event "virtual_start" "Detectados hilos virtuales (demo): $VIRTUAL_THREADS_CHART"
    FIRST_VIRTUAL_FIRED=1
  fi

  clear
  echo "╔════════════════════════════════════════════════════════════════════╗"
  echo "║  MONITOREO JVM - PID: $PID"
  echo "╚════════════════════════════════════════════════════════════════════╝"
  date
  echo
  echo "Hilos (Gráfico): total=$TOTAL_THREADS_CHART | platform=$PLATFORM_THREADS_CHART | virtual=$VIRTUAL_THREADS_CHART"
  echo "Memoria Física (RSS): ${RSS_MB} MB"
  echo "NMT :: Java Heap      reserved=${JH_RES_MB} MB | committed=${JH_COM_MB} MB"
  echo "NMT :: Native Total   reserved=${NAT_RES_MB} MB | committed=${NAT_COM_MB} MB"
  echo "NMT :: Stack          committed=${ST_COM_MB} MB"
  echo
  echo "Ctrl+C para finalizar y generar reporte…"
  sleep $INTERVAL
done