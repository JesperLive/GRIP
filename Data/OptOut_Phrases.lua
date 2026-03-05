-- GRIP: Opt-Out Phrase Data
-- Static opt-out phrase lists for all supported languages (EN, FR, DE, ES).

local ADDON_NAME, GRIP = ...

-- Per-language phrase tables. Each language has a "safe" list (substring matching)
-- and a "risky" list (word-boundary matching via MatchWholeWord).

GRIP.OPT_OUT = {}

GRIP.OPT_OUT.en = {
  safe = {
    "no thanks",
    "no thank you",
    "no ty",
    "not interested",
    "no interest",
    "don't want",
    "dont want",
    "leave me alone",
    "don't whisper",
    "dont whisper",
    "don't message",
    "dont message",
    "don't contact",
    "dont contact",
    "already in a guild",
    "already guilded",
    "have a guild",
    "got a guild",
    "i'm in a guild",
    "im in a guild",
    "reported",
    "reporting you",
    "blocked",
    "nty",
    "i'll pass",
    "ill pass",
    "not for me",
    "thanks but no thanks",
    "just looking",
  },
  risky = {
    "stop",
    "spam",
    "no",
    "pass",
    "nope",
    "nah",
  },
  aggressive = {
    "go away",
    "fuck off",
    "piss off",
    "bugger off",
    "screw off",
    "sod off",
  },
}

GRIP.OPT_OUT.fr = {
  safe = {
    "non merci",
    "pas intéressé",
    "pas intéressée",
    "déjà dans une guilde",
    "non ça va",
    "laisse moi tranquille",
    "ça m'intéresse pas",
  },
  risky = {
    "nope",
  },
}

GRIP.OPT_OUT.de = {
  safe = {
    "nein danke",
    "nicht interessiert",
    "hab schon ne gilde",
    "bin bereits in einer gilde",
    "lass mich in ruhe",
    "bin nicht interessiert",
    "danke nein",
  },
  risky = {
    "nein",
  },
}

GRIP.OPT_OUT.es = {
  safe = {
    "no gracias",
    "no me interesa",
    "ya tengo gremio",
    "no tengo tiempo",
    "no estoy interesado",
    "no estoy interesada",
    "déjame en paz",
  },
  risky = {},
}
