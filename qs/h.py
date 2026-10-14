# Aides pour écrire la banque. Y = année, N = quantité.
def Y(q, y, fact=""): return {"q": q, "v": y, "k": "y", "u": "", "fact": fact}
def N(q, v, unit="", fact=""): return {"q": q, "v": v, "k": "n", "u": unit, "fact": fact}
