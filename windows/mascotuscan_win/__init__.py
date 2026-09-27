# mascotuscan para Windows: la mascota observa a Claude Code, no a cmux.
#
# cmux solo existe en macOS, asi que en Windows no hay `cmux events` que
# traducir. En su lugar, los hooks de Claude Code escriben cada evento a
# ~/.mascotuscan/shell.jsonl y la mascota hace tail de ese archivo. El resto del
# contrato es el mismo del proyecto: seis estados, plantillas con marcadores,
# y el pet pack decide como se ve y como habla.

__version__ = "0.4.0"
