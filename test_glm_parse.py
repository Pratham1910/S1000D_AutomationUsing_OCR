#!/usr/bin/env python
"""Test GLM-OCR parsing with bundled layout model."""
import os
import sys
from pathlib import Path

os.environ['GLMOCR_LAYOUT_MODEL_DIR'] = r'C:\Users\PRATHAMESH\Desktop\OCR\GLM-OCR\dist\Portable\S1000D_Converter_Suite\layout_models\PP-DocLayoutV3_safetensors'

from glmocr import GlmOcr

dotted = {
    'pipeline.maas.enabled': False,
    'pipeline.ocr_api.api_mode': 'ollama_generate',
    'pipeline.ocr_api.api_url': 'http://127.0.0.1:11434/api/generate',
    'pipeline.ocr_api.model': 'glm-ocr:latest',
    'pipeline.layout.model_dir': r'C:\Users\PRATHAMESH\Desktop\OCR\GLM-OCR\dist\Portable\S1000D_Converter_Suite\layout_models\PP-DocLayoutV3_safetensors',
}

pdf_path = Path('document.pdf')
print(f'PDF exists: {pdf_path.exists()}')

with GlmOcr(mode='selfhosted', model='glm-ocr:latest', _dotted=dotted) as parser:
    with open(str(pdf_path), 'rb') as f:
        pdf_bytes = f.read()
    print(f'PDF size: {len(pdf_bytes) / 1024 / 1024:.2f} MB')
    print('Parsing PDF...')
    try:
        results = parser.parse(pdf_bytes)
        print(f'Success! Result type: {type(results).__name__}')
        has_pages = hasattr(results, 'pages')
        print(f'Has pages attribute: {has_pages}')
        if has_pages:
            print(f'Number of pages: {len(results.pages)}')
            if results.pages:
                for i, page in enumerate(results.pages[:2]):
                    print(f'  Page {i}: {type(page).__name__}')
                    if hasattr(page, '__len__'):
                        print(f'    Length: {len(page)}')
    except Exception as e:
        print(f'Error: {type(e).__name__}: {e}')
        import traceback
        traceback.print_exc()
