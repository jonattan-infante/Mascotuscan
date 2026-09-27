// Texto que produce el PROGRAMA, no la mascota.
//
// Nada de aqui tiene personalidad, a proposito: si el programa pusiera
// onomatopeyas o muletillas, un gato acabaria diciendo "*whirr*". La personalidad
// vive en el pack; esto son piezas neutras que las plantillas del pack rellenan,
// mas el ultimo recurso cuando una mascota no trae frase para algo.
//
// Ver docs/adr/0005.

import Foundation

public enum Wording {
    /// Traduce la herramienta a lo que el agente esta haciendo de verdad.
    /// `tool_input` viene redactado en los eventos, asi que el nombre de la
    /// herramienta es todo lo que hay: sirve para el verbo, no para el detalle.
    public static func activity(_ tool: String?) -> String {
        switch tool ?? "" {
        case "Bash", "BashOutput", "KillShell":            return "corriendo comandos"
        case "Edit", "Write", "MultiEdit", "NotebookEdit":  return "editando archivos"
        case "Read":                                        return "leyendo código"
        case "Grep", "Glob":                                return "buscando en el código"
        case "WebFetch", "WebSearch":                       return "consultando la web"
        case "Task", "Agent":                               return "delegando a subagentes"
        case "Skill":                                       return "usando una skill"
        case "AskUserQuestion":                             return "esperando tu respuesta"
        case "TodoWrite", "TaskCreate", "TaskUpdate":       return "organizando el plan"
        case "Artifact":                                    return "publicando un artifact"
        case "":                                            return "arrancando"
        default:                                            return "usando \(tool ?? "")"
        }
    }

    /// " en Fineract" o cadena vacia si no sabemos donde. Trae la preposicion
    /// incluida para que las plantillas lo peguen directo tras una palabra.
    public static func at(_ workspace: String) -> String {
        workspace.isEmpty ? "" : " en \(workspace)"
    }

    /// "y 2 más": lo que se agrega cuando la frase de la mascota habla de un
    /// agente pero hay varios. Neutro, para no pisar su voz.
    public static func andOthers(_ count: Int) -> String {
        count <= 0 ? "" : (count == 1 ? " Y otro más." : " Y otros \(count) más.")
    }

    /// Ultimo recurso: la mascota no trae frase para esa clase y todavia no se le
    /// han generado. Informa sin actuar ningun personaje.
    public static func plain(_ text: String) -> String { text }
}
