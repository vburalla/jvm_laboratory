public class Calculator {

    private static final double PI = 3.141592653589793;

    public int add(int a, int b) {
        return a + b;
    }

    public int subtract(int a, int b) {
        return a - b;
    }

    public int multiply(int a, int b) {
        return a * b;
    }

    public int divide(int a, int b) {
        return  a / b;
    }

    public double circleLength(int radius) {
        return 2 * PI * radius;
    }
}
