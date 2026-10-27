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

    /// Instrucciones con el material del usuario. El material va primero (los documentos largos rinden
    /// mejor antes de las instrucciones) y no cambia entre capturas, así que la caché de prompts lo reutiliza.
    public static func system(context: String?) -> String {
        guard let context, !context.isEmpty else { return system }
        return """
            Material de referencia que cargó el usuario (apuntes, banco de preguntas o temario del curso):
            <contexto>
            \(context)
            </contexto>

            \(system)
            Si la pregunta aparece en el material o este la responde, básate en él aunque difiera de tu \
            conocimiento general; si no, responde con lo que sabes.
            """
    }
}
