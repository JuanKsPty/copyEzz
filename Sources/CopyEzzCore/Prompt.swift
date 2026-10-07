/// Instrucciones compartidas por los tres motores (mismo texto que la versión Python).
public enum Prompt {
    public static let system = """
        Recibes una captura de pantalla completa. En algún lugar hay una pregunta de examen o quiz \
        (opción múltiple, verdadero/falso o respuesta corta). Ignora el resto de la pantalla \
        (pestañas, menús, temporizadores, botones).

        Responde en exactamente dos líneas, sin markdown:
        Línea 1: la respuesta correcta con el formato "<letra>) <texto de la opción>", por ejemplo "b) CHARTOROWID". \
        Si hay varias correctas: "a) X, c) Y". Si es verdadero/falso: "Verdadero" o "Falso". \
        Si es de respuesta corta: la respuesta en pocas palabras.
        Línea 2: la justificación en una sola frase.
        Si no hay ninguna pregunta visible, responde solo: SIN PREGUNTA
        """

    public static let userText = "Responde la pregunta de esta captura."
}
