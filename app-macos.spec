# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['app.py'],
    pathex=[],
    binaries=[],
    datas=[('icon.png', '.'), ('avatar.png', '.'), ('assets', 'assets'), ('llama', 'llama'), ('crispasr', 'crispasr'), ('project', 'project'), ('separate', 'separate'), ('plugins', 'plugins'), ('ffmpeg', 'ffmpeg'), ('translate', 'translate'), ('translation_guidelines','translation_guidelines')],
    hiddenimports=['tiktoken_ext.openai_public', 'tiktoken_ext'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['torch','onnx','onnxruntime','librosa','soundfile'],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='VoiceTransl',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='VoiceTransl',
)

app = BUNDLE(
    coll,
    name='VoiceTransl.app',
    icon='icon.icns',
    bundle_identifier='com.voicetransl.app',
    # 不写 info_plist 时 PyInstaller 会填默认的 0.0.0，
    # 导致「显示简介」里永远是 0.0.0，排障时无法从 app 自身读出版本。
    # 发版时记得同步改这里与 README 里的版本串。
    info_plist={
        'CFBundleShortVersionString': '1.30',
        'CFBundleVersion': '1.30',
    },
)
