# 🧪 Laboratorio de Platform Threads vs Virtual Threads en Java 21

# 1. 🎯 Objetivo del Experimento

Comparar el comportamiento de la clase:

    ThreadsDemo <thread_type> <num_tasks>

donde:

-   **p** → Platform Threads\
-   **v** → Virtual Threads\
-   **num_tasks** → número de tareas/hilos a crear

El experimento se ejecutará en un contenedor con **256 MB de memoria**,
sin tener en cuenta los límites de PIDs para la prueba principal.

Queremos observar:

  ------------------------------------------------------------------------
Tipo de Hilo  Consume Memoria Nativa    Escalable en contenedor pequeño
  ------------- ------------------------- --------------------------------
Platform      Sí (stack nativo por      ❌ No
hilo)

Virtual       No (stack en heap,        ✔ Sí
multiplexado)
  ------------------------------------------------------------------------

# 2. 🏗️ Preparación del Entorno

## 2.1 Guardar el Código

Guarda tu clase como:

    ThreadsDemo.java

## 2.2 Crear el Pod

``` bash
podman pod rm -f laboratorio-threads-limitado
podman pod create --name laboratorio-threads-limitado
```

# 3. 🚀 Ejecución de la Prueba

## 3.1 Iniciar un contenedor con Java dentro del Pod

``` bash
podman run --rm -it --pod laboratorio-threads-limitado \
  --memory 256m \
  -v $(pwd):/app -w /app \
  eclipse-temurin:21-jdk-jammy \
  bash -c "javac ThreadsDemo.java && java ThreadsDemo.java p 10"
```

También puedes entrar al contenedor:

``` bash
javac ThreadsDemo.java
```

# 4. 🧪 Prueba 1 --- Platform Threads (10 hilos)

    java ThreadsDemo p 10

### 📌 Resultados Esperados

-   Los 10 hilos se ejecutarán correctamente.
-   El tiempo será similar al de Virtual Threads.
-   No habrá errores.

### 🧠 Por qué

-   10 Platform Threads usan poca memoria nativa.
-   256 MB son suficientes.

# 5. 🧪 Prueba 2 --- Platform Threads (5000 hilos)

    java ThreadsDemo p 5000

### 📌 Resultados Esperados

Error:

    OutOfMemoryError: unable to create native thread

### 🧠 Por qué

-   Cada hilo nativo necesita stack (\~1 MB).
-   Con 256 MB, 5000 hilos exceden la memoria nativa disponible.
-   El fallo ocurre en `thread.start()`.

# 6. 🧪 Prueba 3 --- Virtual Threads (10 y 5000 hilos)

    java ThreadsDemo v 10
    java ThreadsDemo v 5000

### 📌 Resultados Esperados

-   Todo funciona.
-   Sin errores.
-   Muy bajo consumo de memoria.

### 🧠 Por qué

-   No usan stack nativo.
-   Se multiplexan sobre carrier threads.
-   Cada hilo usa pocos KB.

# 7. 📊 Comparativa

Característica    Platform Threads   Virtual Threads
  ----------------- ------------------ -----------------
Stack nativo      ✔ Sí (\~1MB)       ❌ No
Máximo práctico   Decenas/cientos    Miles
Riesgo OOM        Muy alto           Muy bajo
Escalabilidad     Limitada           Excelente

# 8. 🧩 Conclusión

-   Platform Threads no escalan en contenedores pequeños.
-   Virtual Threads sí.
-   Para cargas concurrentes en contenedores, Java 21 recomienda Virtual
    Threads.

# 9. 📝 Nota sobre PIDs

Para ver límite de PIDs:

    ulimit -u -> Máximo de tasks del kernel por usuario
no limita el número de “hilos en Java”, sino el número de procesos/hilos del kernel (“tasks”) simultáneos que un usuario puede tener activos a la vez.

En contenedor:

``` bash
podman run --rm -it \
  --pids-limit 400 \
  --memory 256m \
  eclipse-temurin:21-jdk-jammy \
  bash -c "ulimit -u"
```
