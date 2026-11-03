"""FastAPI + FFmpeg smoke test in a temporary PakesY folder; doesn't touch real data."""
from pathlib import Path
from tempfile import TemporaryDirectory
import importlib.util
import shutil
import subprocess
import sqlite3
from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parent
OWNER_EMAIL = 'pa9783531@gmail.com'

with TemporaryDirectory(prefix='pakesy-smoke-') as root:
    temp = Path(root)
    (temp / 'assets').mkdir()
    (temp / 'media').mkdir()
    shutil.copy2(ROOT / 'app.py', temp / 'app.py')
    shutil.copy2(ROOT / 'index.html', temp / 'index.html')
    shutil.copytree(ROOT / 'assets', temp / 'assets', dirs_exist_ok=True)
    for clip in (ROOT / 'media').glob('demo_*'):
        shutil.copy2(clip, temp / 'media' / clip.name)
    spec = importlib.util.spec_from_file_location('pakesy_smoketest', temp / 'app.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with TestClient(module.app) as client:
        assert client.get('/api/status').json()['authenticated'] is False
        assert client.get('/api/feed').status_code == 401
        assert client.post('/api/register', json={'email': 'someone@example.com', 'password': 'supersecretpass'}).status_code == 403
        assert client.post('/api/register', json={'email': OWNER_EMAIL, 'password': 'supersecretpass'}).status_code == 200
        assert client.get('/api/status').json()['featured_account'] is True
        assert client.post('/api/register', json={'email': OWNER_EMAIL, 'password': 'supersecretpass'}).status_code == 409
        empty = client.get('/api/feed').json()
        assert empty['videos'] == []
        assert empty['stats']['videos'] == 0
        assert empty['stats']['likes'] == 0 and empty['stats']['comments'] == 0
        assert empty['stats']['demo_earnings'] == 0
        assert 'profiles' not in empty['stats']
        # Re-loading/re-entering the feed before an upload must not create activity.
        assert client.get('/api/feed').json()['stats'] == empty['stats']

        vid = temp / 'sample.mp4'
        subprocess.run(['ffmpeg', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=10', '-f', 'lavfi', '-i', 'sine=frequency=440', '-t', '2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', str(vid)], check=True, capture_output=True)
        with vid.open('rb') as source:
            response = client.post('/api/upload', files={'file': ('bedwars.mp4', source, 'video/mp4')}, data={'title': 'First BedWars Test', 'description': 'Private clip', 'auto_edit': 'true'})
        assert response.status_code == 200, response.text
        vid_id = response.json()['video_id']
        feed = client.get('/api/feed').json()
        assert len(feed['videos']) == 1, 'only the uploaded video should show on day one'
        assert feed['videos'][0]['id'] == vid_id
        assert feed['videos'][0]['is_owner'] and feed['videos'][0]['is_featured']
        assert feed['videos'][0]['comments'] >= 18
        assert feed['stats']['videos'] == 1 and feed['stats']['likes'] > 0
        assert client.get(feed['videos'][0]['poster_url']).status_code == 200
        assert client.get(feed['videos'][0]['url']).status_code == 200
        assert len(client.get('/api/videos/' + vid_id + '/comments').json()['comments']) >= 18

        # Standalone posts attributed to other actors must not be promoted.
        with sqlite3.connect(module.DB) as db:
            db.execute('''INSERT INTO videos(id,title,description,file_name,actor_id,auto_edited,created_at,views,likes,target_comments,target_likes,activity_start,duration,uploader_email)
                         VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
                       ('other123', 'Other creator', '', feed['videos'][0]['file_name'], 42, 0, 0, 0, 0, 0, 0, 0, 2, 'other@example.com'))
            db.commit()
        assert all(v['id'] != 'other123' for v in client.get('/api/feed').json()['videos'])
        assert client.post('/api/videos/other123/simulate', json={'count': 500, 'bot_videos': 2}).status_code == 403

        boost = client.post('/api/videos/' + vid_id + '/simulate', json={'count': 500, 'bot_videos': 2})
        assert boost.status_code == 200, boost.text
        feed = client.get('/api/feed').json()
        assert feed['videos'][0]['id'] == vid_id
        assert feed['videos'][0]['comments'] >= 500
        assert len(feed['videos']) == 3
        assert all(v['likes'] == 0 for v in feed['videos'][1:]), 'remixes do not go viral'
        assert all(v['author']['name'] == 'PakesY Highlights' for v in feed['videos'][1:])
        assert client.get('/api/feed?tab=trending').json()['videos'][0]['id'] == vid_id
        text = [c['body'] for c in client.get('/api/videos/' + vid_id + '/comments?limit=500').json()['comments']]
        assert len(set(text)) == len(text)
        assert client.post('/api/videos/' + vid_id + '/comment', json={'body': 'Great run!'}).status_code == 200
        assert client.delete('/api/videos/' + vid_id).status_code == 200
        assert client.get('/api/feed').json()['videos'] == []
        assert client.post('/api/logout').status_code == 200
        assert client.get('/api/feed').status_code == 401
        assert client.post('/api/login', json={'email': OWNER_EMAIL, 'password': 'supersecretpass'}).status_code == 200
        assert client.get('/api/feed').json()['stats']['likes'] == 0
        print('PASS: email-only owner, empty initial feed, upload-triggered activity, 500 comments, exclusive trending, remix limits, auto-edit and login')
