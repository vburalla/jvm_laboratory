import java.util.concurrent.*;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;

public class ThreadMemoryDemo {

    private static final int THREAD_COUNT = 500;
    private static final int SLEEP_TIME_MS = 20000; // 20 segundos
    private static final Path VIRTUAL_THREAD_COUNT_FILE = Path.of("virtual_threads.state");

    public static void main(String[] args) throws Exception {
        // Inicializa el archivo de estado
        writeVirtualThreadCount(0); 

        System.out.println("=== DEMO: Platform Threads vs Virtual Threads ===");
        System.out.println("Threads a crear: " + THREAD_COUNT);
        System.out.println();
        System.out.println("PID del proceso: " + ProcessHandle.current().pid());
        System.out.println("Puedes conectar VisualVM o usar:");
        System.out.println("  jcmd " + ProcessHandle.current().pid() + " VM.native_memory summary");
        System.out.println("  top -p " + ProcessHandle.current().pid());
        pause("Conecta tu herramienta de monitoreo y pulsa una tecla para comenzar...");

        printMemoryStats("BASELINE (inicio del programa)");
        System.out.println("\n" + "=".repeat(90) + "\n");

        // Test 1: Platform Threads
        testPlatformThreads();

        System.out.println("\n" + "=".repeat(90));
        pause("Pulsa una tecla para ejecutar el GC tras finalizar los platform threads...");
        System.gc();
        printMemoryStats("DESPUÉS DE GC (platform threads cerrados)");
        System.out.println("=".repeat(90) + "\n");

        // Test 2: Virtual Threads
        // NOTIFICACIÓN AL MONITOR: Activamos el conteo real de hilos virtuales
        writeVirtualThreadCount(THREAD_COUNT); 
        testVirtualThreads();
        // NOTIFICACIÓN AL MONITOR: Desactivamos el conteo
        writeVirtualThreadCount(0); 

        System.out.println("\n" + "=".repeat(90));
        pause("Pulsa una tecla para ejecutar el GC tras finalizar los virtual threads...");
        System.gc();
        printMemoryStats("FINAL (todos los threads cerrados)");
        System.out.println("=".repeat(90));

        System.out.println("\nDemo completada. Presiona Ctrl+C para salir o espera...");
        Thread.sleep(30000);
    }

    private static void testPlatformThreads() throws Exception {
        System.out.println("### TEST 1: PLATFORM THREADS ###");
        System.out.println("Creando ThreadPool con " + THREAD_COUNT + " threads...");

        ExecutorService executor = Executors.newFixedThreadPool(THREAD_COUNT);
        CountDownLatch latch = new CountDownLatch(THREAD_COUNT);

        printMemoryStats("Después de crear el ThreadPool (sin tareas aún)");
        System.out.println("""
            ➤ En este punto:
              - Se ha creado el ThreadPoolExecutor y estructuras internas (cola, locks...).
              - Los Platform Threads aún NO se han lanzado.
              - La memoria off-heap (pilas nativas) todavía no ha aumentado.
            """);
        pause("Pulsa una tecla para enviar las tareas al ThreadPool...");

        long startTime = System.currentTimeMillis();

        for (int i = 0; i < THREAD_COUNT; i++) {
            executor.submit(() -> {
                try {
                    Thread.sleep(SLEEP_TIME_MS);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                } finally {
                    latch.countDown();
                }
            });
        }

        System.out.println("Tareas enviadas en " + (System.currentTimeMillis() - startTime) + " ms");
        printMemoryStats("Después de enviar las tareas (threads en ejecución o durmiendo)");
        System.out.println("""
            ➤ Ahora:
              - Se han creado los Platform Threads reales.
              - Cada hilo tiene su pila nativa (off-heap) de varios cientos de KB.
              - También se han creado objetos Thread, CountDownLatch, Runnable, etc., en el heap.
              - El heap ha aumentado ligeramente por los objetos de control Java.
            """);
        pause("Pulsa una tecla para continuar y esperar a que terminen los threads...");

        latch.await();
        executor.shutdown();
        executor.awaitTermination(5, TimeUnit.SECONDS);

        printMemoryStats("Después de cerrar el ThreadPoolExecutor");
        System.out.println("""
            ➤ En este punto:
              - Todos los threads han terminado su ejecución.
              - El ThreadPool mantiene referencias a los objetos Thread terminados.
              - El GC todavía no ha liberado la memoria de esos objetos.
              - Por eso el heap sigue más alto que al inicio.
            """);
    }

    private static void testVirtualThreads() throws Exception {
        System.out.println("\n### TEST 2: VIRTUAL THREADS ###");
        System.out.println("Creando Executor con Virtual Threads...");

        ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor();
        CountDownLatch latch = new CountDownLatch(THREAD_COUNT);

        printMemoryStats("Después de crear el VirtualThreadPerTaskExecutor (sin tareas aún)");
        System.out.println("""
            ➤ En este punto:
              - El executor de virtual threads no crea threads preexistentes.
              - No hay stacks nativos grandes (usa un stack pequeño en heap).
              - Prácticamente sin aumento en heap ni off-heap todavía.
            """);
        pause("Pulsa una tecla para enviar las tareas a los virtual threads...");

        long startTime = System.currentTimeMillis();

        for (int i = 0; i < THREAD_COUNT; i++) {
            executor.submit(() -> {
                try {
                    Thread.sleep(SLEEP_TIME_MS);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                } finally {
                    latch.countDown();
                }
            });
        }

        System.out.println("Tareas enviadas en " + (System.currentTimeMillis() - startTime) + " ms");
        printMemoryStats("Después de enviar las tareas (virtual threads activos o durmiendo)");
        System.out.println("""
            ➤ Ahora:
              - Se han creado los virtual threads (ligeros, gestionados por la JVM).
              - Cada virtual thread usa un stack muy pequeño en heap.
              - No hay stacks nativos dedicados (off-heap casi no varía).
              - El heap aumenta ligeramente por los objetos de infraestructura.
            """);
        pause("Pulsa una tecla para continuar y esperar a que terminen los virtual threads...");

        latch.await();
        executor.shutdown();
        executor.awaitTermination(5, TimeUnit.SECONDS);

        printMemoryStats("Después de cerrar el executor de virtual threads");
        System.out.println("""
            ➤ En este punto:
              - Los virtual threads terminados se liberan rápidamente.
              - No quedan estructuras retenidas.
              - El heap debería bajar más que con los platform threads.
            """);
    }

    private static void printMemoryStats(String label) {
        Runtime runtime = Runtime.getRuntime();
        long totalMemory = runtime.totalMemory();
        long freeMemory = runtime.freeMemory();
        long usedMemory = totalMemory - freeMemory;
        long maxMemory = runtime.maxMemory();

        System.out.println("\n--- " + label + " ---");
        System.out.printf("Heap usado:      %,d MB%n", usedMemory / (1024 * 1024));
        System.out.printf("Heap total:      %,d MB%n", totalMemory / (1024 * 1024));
        System.out.printf("Heap máximo:     %,d MB%n", maxMemory / (1024 * 1024));

        System.out.println("\n⚠️  Recuerda:");
        System.out.println("   - Este valor refleja solo el heap (objetos Java).");
        System.out.println("   - Las pilas nativas de los platform threads están fuera del heap (off-heap).");
        System.out.println("   - Para ver la memoria nativa: jcmd " + ProcessHandle.current().pid() + " VM.native_memory summary");
    }

    /**
     * Escribe el número de hilos virtuales creados/activos en un archivo de estado.
     * @param count El número de hilos virtuales.
     */
    private static void writeVirtualThreadCount(int count) {
        try {
            Files.writeString(VIRTUAL_THREAD_COUNT_FILE, String.valueOf(count), 
                StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING);
            System.out.println("\n[ESTADO] Hilos virtuales escritos en archivo: " + count);
        } catch (IOException e) {
            System.err.println("Error al escribir el archivo de estado de hilos virtuales: " + e.getMessage());
        }
    }

    private static void pause(String message) throws IOException {
        System.out.println("\n" + message);
        System.out.println("Presiona ENTER para continuar...");
        System.in.read();
        // Consumir el resto de la línea (\n o \r\n) tras ENTER
        if (System.in.available() > 0) {
            System.in.read();
        }
    }
}