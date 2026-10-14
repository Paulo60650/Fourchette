"""Assemble www/index.html (APK) et artifact.html (aperçu) à partir du gabarit et de questions.json."""
import re, os
data = open('questions.json', encoding='utf-8').read()
assert '</script' not in data
tpl = open('app.template.html', encoding='utf-8').read()
assert tpl.count('/*QDATA*/null') == 1
tpl = tpl.replace('/*QDATA*/null', data)

# aperçu (fragment, polices Google)
open('artifact.html', 'w', encoding='utf-8').write(tpl)

# APK : document complet, sans polices externes
title = re.search(r'<title>.*?</title>', tpl).group(0)
style = re.search(r'<style>.*?</style>', tpl, re.S).group(0)
rest = tpl[tpl.index('</style>') + len('</style>'):]
doc = ('<!doctype html>\n<html lang="fr">\n<head>\n<meta charset="utf-8">\n'
       '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover,user-scalable=no">\n'
       '<meta name="theme-color" content="#12062B">\n<meta name="color-scheme" content="dark light">\n'
       + title + '\n' + style + '\n</head>\n<body>\n' + rest.strip() + '\n</body>\n</html>\n')
os.makedirs('www', exist_ok=True)
open('www/index.html', 'w', encoding='utf-8').write(doc)
print('www/index.html', len(doc), 'octets ; artifact.html', len(tpl))
