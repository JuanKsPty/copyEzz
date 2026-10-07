public enum CaptureSizing {
    /// Lado máximo que aprovechan los modelos de visión; más grande solo cuesta tokens y latencia.
    public static let maxEdge = 1568

    /// Tamaño final en píxeles manteniendo la proporción; nunca agranda.
    public static func scaled(width: Int, height: Int, maxEdge: Int = maxEdge) -> (width: Int, height: Int) {
        let longest = max(width, height)
        guard longest > maxEdge else { return (width, height) }
        let factor = Double(maxEdge) / Double(longest)
        return (max(1, Int((Double(width) * factor).rounded())), max(1, Int((Double(height) * factor).rounded())))
    }
}
