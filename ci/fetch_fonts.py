"""Scarica i caratteri come TTF dentro assets/google_fonts, con i nomi che il pacchetto
google_fonts cerca tra gli asset (così funzionano subito e anche offline)."""
import re, urllib.request, os

OUT = 'assets/google_fonts'
FAMILIES = {
    'Playfair Display': ['400', '400italic', '500', '600', '600italic', '700', '700italic'],
    'Lora': ['400', '400italic', '500', '500italic', '600', '700', '700italic'],
    'Montserrat': ['500', '600', '700'],
    'Source Sans 3': ['400', '400italic', '600', '700'],
}
NAMES = {100: 'Thin', 200: 'ExtraLight', 300: 'Light', 400: 'Regular', 500: 'Medium', 600: 'SemiBold', 700: 'Bold', 800: 'ExtraBold', 900: 'Black'}
UA = 'Mozilla/5.0 (Windows NT 6.1) AppleWebKit/534.30 (KHTML, like Gecko) Safari/534.30'  # vecchio browser → TTF

os.makedirs(OUT, exist_ok=True)
for fam, variants in FAMILIES.items():
    url = 'https://fonts.googleapis.com/css?family=' + fam.replace(' ', '+') + ':' + ','.join(variants)
    try:
        css = urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': UA}), timeout=30).read().decode()
    except Exception as e:
        print('salto', fam, e)
        continue
    for block in re.findall(r'@font-face\s*\{(.*?)\}', css, re.S):
        style = re.search(r'font-style:\s*(\w+)', block).group(1)
        weight = int(re.search(r'font-weight:\s*(\d+)', block).group(1))
        m = re.search(r'url\((https://[^)]+)\)', block)
        if not m:
            continue
        name = NAMES[weight]
        if style == 'italic':
            name = 'Italic' if name == 'Regular' else name + 'Italic'
        fn = f"{OUT}/{fam.replace(' ', '')}-{name}.ttf"
        try:
            data = urllib.request.urlopen(m.group(1), timeout=60).read()
            if data[:4] in (b'\x00\x01\x00\x00', b'true', b'OTTO'):
                open(fn, 'wb').write(data)
                print('ok', fn, len(data))
            else:
                print('non TTF', fn)
        except Exception as e:
            print('errore', fn, e)
