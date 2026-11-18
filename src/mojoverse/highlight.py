"""Add current Mojo keywords to Pygments' Mojo 24.2 lexer."""

from pygments.lexer import inherit, words
from pygments.lexers.mojo import MojoLexer
from pygments.token import Keyword


class CurrentMojoLexer(MojoLexer):
    name = "Mojo"
    aliases = ["mojo-current"]
    tokens = {
        "root": [
            (words(("comptime", "raises", "mut", "imm", "out", "deinit", "ref", "var", "thin"), suffix=r"\b"), Keyword),
            inherit,
        ],
    }
