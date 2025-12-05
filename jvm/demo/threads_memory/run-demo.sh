#!/bin/bash

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║  Demo: Platform Threads vs Virtual Threads - Impacto en Memoria   ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""

# Verificar Java 21+
JAVA_VERSION=$(java -version 2>&1 | head -n 1 | cut -d'"' -f2 | cut -d'.' -f1)
if [ "$JAVA_VERSION" -lt 21 ]; then
    echo "❌ Error: Se requiere Java 21 o superior"
    echo "   Versión actual: $(java -version 2>&1 | head -n 1)"
    exit 1
fi

echo "✓ Java version: $(java -version 2>&1 | head -n 1)"
echo ""

# Compilar
echo "📦 Compilando ThreadMemoryDemo.java..."
javac ThreadMemoryDemo.java

if [ $? -ne 0 ]; then
    echo "❌ Error al compilar"
    exit 1
fi

echo "✓ Compilación exitosa"
echo ""

echo "════════════════════════════════════════════════════════════════════"
echo "🚀 INICIANDO APLICACIÓN"
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "⚠️  IMPORTANTE: Abre otra terminal y ejecuta:"
echo ""
echo "    ./monitor.sh"
echo ""
echo "    Luego selecciona la opción 3 (Monitoreo continuo)"
echo ""
echo "════════════════════════════════════════════════════════════════════"
echo ""
echo "🔧 Configuración:"
echo "   - Native Memory Tracking: Habilitado"
echo "   - Heap mínimo: 50 MB"
echo "   - Heap máximo: 512 MB"
echo "   - Threads a crear: 500"
echo ""
echo "Iniciando en 3 segundos..."
sleep 3
echo ""

# Ejecutar con NMT habilitado
java -XX:NativeMemoryTracking=detail \
    -Xss 1m
     -Xms50m \
     -Xmx512m \
     ThreadMemoryDemo

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "Demo finalizada"
echo "════════════════════════════════════════════════════════════════════"