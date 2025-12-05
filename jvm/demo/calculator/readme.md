# Ver el bytecode de la clase `Calculator`

Este proyecto contiene la clase Java `Calculator` ubicada en `jvm/demo/calculator/Calculator.java`.

## Requisitos

- JDK instalado (Java Development Kit)
- Acceso a la terminal

## Proceso para ver el bytecode

1. **Compila la clase:**

   ```bash
   cd jvm/demo/calculator/
   javac Calculator.java

1. Ver solo el bytecode del código (-c):


javap -c Calculator
Esto muestra únicamente las instrucciones de bytecode generadas por el código fuente.


2. Ver el bytecode completo (-v):


javap -c -v Calculator
El parámetro -v muestra información detallada, incluyendo el bytecode, constantes, atributos y metadatos de la clase.
Notas
Asegúrate de estar en el directorio raíz del proyecto al ejecutar los comandos.
El archivo .class se generará en la misma ruta que el archivo fuente tras la compilación.