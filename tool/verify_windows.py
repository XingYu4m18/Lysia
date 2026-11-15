"""Exercise the packaged app with a WAV file and optionally system playback.

Usage: python tool/verify_windows.py path/to/lysia.exe public-test.wav report-dir
Only the explicitly supplied public test WAV is played or submitted for recognition.
"""
import json
import pathlib
import subprocess
import sys
import time

exe, wav, reports = [pathlib.Path(p).resolve() for p in sys.argv[1:4]]
reports.mkdir(parents=True, exist_ok=True)

def run(name, playback):
    output=reports/f'{name}.json'
    output.write_text('{}',encoding='utf-8')
    args=[str(exe),f'--verify-output={output}',f'--verify-dir={reports/name}']
    if not playback:args.append(f'--verify-file={wav}')
    process=subprocess.Popen(args,cwd=exe.parent)
    player=None
    try:
        deadline=time.monotonic()+90
        while time.monotonic()<deadline:
            try:report=json.loads(output.read_text(encoding='utf-8'))
            except (ValueError,OSError):report={}
            if report.get('stage')=='started' and playback and player is None:
                escaped=str(wav).replace("'","''")
                command=f"$player=New-Object System.Media.SoundPlayer; $player.SoundLocation='{escaped}'; $player.Load(); $player.PlayLooping(); Start-Sleep -Seconds 35; $player.Stop()"
                player=subprocess.Popen(['powershell','-NoProfile','-Command',command],creationflags=subprocess.CREATE_NO_WINDOW)
            if report.get('stage') in ('complete','failed'):
                print(name,json.dumps(report,ensure_ascii=False),flush=True)
                if report['stage']!='complete' or not report.get('netease') or not report.get('kugou'):
                    raise RuntimeError(f'{name}: recognition did not pass')
                process.wait(timeout=15)
                return
            if process.poll() is not None:raise RuntimeError(f'{name}: app exited before reporting: {process.returncode}')
            time.sleep(.25)
        raise TimeoutError(f'{name}: timed out')
    finally:
        if player is not None and player.poll() is None:player.terminate();player.wait(timeout=10)
        if process.poll() is None:process.terminate();process.wait(timeout=10)

run('file-recognition',False)
run('system-loopback',True)
