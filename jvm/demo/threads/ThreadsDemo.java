import java.util.logging.Logger;

public class ThreadsDemo {

    private static final Integer DEFAULT_NUM_TASKS = 1000;
    private static final String DEFAULT_TYPE_THREADS = "p";

    private static final Logger logger = Logger.getLogger(ThreadsDemo.class.getName());

    private static void doSomething(int id) {
        try {
            String threadName = Thread.currentThread().toString();
            logger.info(threadName + " [TASK=" + id + "] START");
            Thread.sleep(2000);
            logger.info(threadName + " [TASK=" + id + "] END");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    public static void main(String[] args) throws InterruptedException {

        String typeThreads = args.length > 0 && args[0] != null ? args[0] : DEFAULT_TYPE_THREADS;
        int numTasks = args.length > 1 && args[1] != null ? Integer.parseInt(args[1]) : DEFAULT_NUM_TASKS;

        if ((!typeThreads.equals("v") && !typeThreads.equals("p")) || numTasks <= 0) {
            logger.info("Use: java VirtualThreads <thread_type> <num_tasks>");
            logger.info("  <thread_type>: 'v' for virtual, 'p' for platform (default value)" );
            logger.info("  <num_tareas>: integer number > 0 (1000 default value");
            return;
        }

        logger.info("Starting " + numTasks + " virtual threads...");
        var threads = new java.util.ArrayList<Thread>();
        long time = System.currentTimeMillis();

        for (int i = 0; i < numTasks; i++) {
            final int taskId = i;
            if(typeThreads.equals("p")) {
                Thread thread = Thread.ofPlatform()
                        .name("platform-worker-" + i, 0)
                        .start(() -> doSomething(taskId));
                threads.add(thread);
            } else {
                Thread vThread = Thread.ofVirtual()
                        .name("virtual-worker-" + i, 0)
                        .start(() -> doSomething(taskId));
                threads.add(vThread);
            }
        }

        for (Thread t : threads) {
            t.join();
        }

        logger.info("\n✅ All threads finished. Total time: "
                + (System.currentTimeMillis() - time) + "ms");
    }
}