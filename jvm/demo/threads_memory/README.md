# 🚀 Instrucciones Rápidas

## Preparación

```bash
# Dar permisos de ejecución
chmod +x run-demo.sh monitor.sh
```

## Ejecución

### Terminal 1: Ejecutar la aplicación
```bash
./run-demo.sh
```

### Terminal 2: Monitorizar (mientras corre la app)
```bash
./monitor_old.sh
```

---

## 📊 Qué observar

### Durante PLATFORM THREADS (primeros ~40 segundos):

```
📊 THREADS (Memoria Nativa)
-          Thread (reserved=2048000KB, committed=2048000KB)
                (thread #2001)
                (stack: reserved=2044928KB, committed=2044928KB)

💾 MEMORIA DEL PROCESO
RSS: ~2500 MB  ← ¡2000 threads × ~1MB cada uno!
```

**Fórmula**: RSS ≈ Heap (256MB) + Threads (2000MB) + Overhead (300MB) = ~2500MB

### Durante VIRTUAL THREADS (siguientes ~40 segundos):

```
📊 THREADS (Memoria Nativa)
-          Thread (reserved=102400KB, committed=102400KB)
                (thread #10)  ← Solo ~10 carrier threads!
                (stack: reserved=102400KB, committed=102400KB)

💾 MEMORIA DEL PROCESO
RSS: ~400 MB  ← ¡Sin overhead de threads!
```

**Diferencia**: ~2100 MB menos de memoria con virtual threads 🎉

---

## 🔍 Comandos Manuales Útiles

Si el script no funciona, ejecuta manualmente:

```bash
# Obtener el PID
PID=$(jps | grep ThreadMemoryDemo | awk '{print $1}')

# Ver memoria nativa (incluye threads)
jcmd $PID VM.native_memory summary

# Ver memoria total del proceso
ps aux | grep $PID | grep -v grep

# Monitoreo continuo manual (cada 3 segundos)
while true; do 
  clear
  echo "=== MEMORIA ==="
  ps aux | grep $PID | grep -v grep
  jcmd $PID VM.native_memory summary | grep -A 2 "Thread"
  sleep 3
done
```

---

## ⚠️ Troubleshooting

### "OutOfMemoryError: unable to create native thread"

Esto es normal si tu sistema tiene límites bajos. Opciones:

1. **Reducir threads** en el código (edita `THREAD_COUNT = 2000` a `1000`)
2. **Aumentar límites** del sistema:
   ```bash
   ulimit -u 10000  # Más procesos
   ulimit -s 2048   # Stack más pequeño
   ```

### El monitor no muestra Native Memory Tracking

Verifica que ejecutaste con `-XX:NativeMemoryTracking=detail`. 

Usa el script `run-demo.sh` que ya lo incluye.

El proceso genera un reporte en la carpeta monitor-report en htlml para visualizar los resultados obtenidos.

### "Unknown diagnostic command"

Algunos comandos de `jcmd` no funcionan igual en todas las versiones de Java/macOS.
El nuevo script ya está adaptado para funcionar correctamente.

---

## 📈 Resultados Esperados

| Métrica | Platform Threads (2000) | Virtual Threads (2000) |
|---------|-------------------------|------------------------|
| **Memoria Heap** | ~250 MB | ~300 MB |
| **Memoria Nativa (threads)** | ~2000 MB | ~10 MB |
| **RSS Total** | ~2500 MB | ~400 MB |
| **Tiempo creación** | 100-300 ms | 10-50 ms |

**Conclusión**: Los virtual threads usan **~85% menos memoria** y se crean **~5x más rápido**.

---

## 💡 Puntos Clave

1. **Platform Threads**: Cada uno reserva ~1MB en memoria nativa (stack)
2. **Virtual Threads**: Son objetos Java ligeros que comparten pocos carrier threads
3. **La memoria nativa NO se ve en VisualVM** - Necesitas NMT o mirar RSS
4. **RSS = Heap + Nativa + Overhead** - Es la memoria real del proceso

---

## 📚 Más Info

- [JEP 444: Virtual Threads](https://openjdk.org/jeps/444)
- [Native Memory Tracking Guide](https://docs.oracle.com/en/java/javase/21/vm/native-memory-tracking.html)