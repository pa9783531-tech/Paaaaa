"""Multi-user regression test for featured-only promotion and upload-triggered activity."""
from pathlib import Path
from tempfile import TemporaryDirectory
import importlib.util
import shutil
import sqlite3
import subprocess
import time
from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parent
PRIMARY = 'pa9783531@gmail.com'
OTHER = 'user2@example.net'

with TemporaryDirectory(prefix='pakesy-two-users-') as folder:
    base = Path(folder)
    shutil.copy2(ROOT/'app.py', base/'app.py')
    shutil.copy2(ROOT/'index.html', base/'index.html')
    shutil.copytree(ROOT/'assets', base/'assets')
    (base/'media').mkdir()
    spec=importlib.util.spec_from_file_location('pakesy_test_multi',base/'app.py')
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    clip=base/'input.mp4'
    subprocess.run(['ffmpeg','-y','-loglevel','error','-f','lavfi','-i','color=c=blue:s=160x90:r=8', '-t','1', '-c:v','libx264',str(clip)],check=True)
    with TestClient(module.app) as owner, TestClient(module.app) as user:
        assert user.post('/api/register',json={'email':OTHER,'password':'testing1234'}).status_code==403
        assert owner.post('/api/register',json={'email':PRIMARY,'password':'testing1234'}).status_code==200
        assert owner.get('/api/feed').json()['stats']['videos']==0
        assert user.post('/api/register',json={'email':OTHER,'password':'testing1234'}).status_code==200
        assert user.get('/api/status').json()['featured_account'] is False
        assert owner.get('/api/status').json()['featured_account'] is True
        assert user.get('/api/feed').json()['stats']['videos']==0

        with clip.open('rb') as f:
            resp=user.post('/api/upload',files={'file':('another.mp4',f,'video/mp4')}, data={'title':'Other Upload', 'auto_edit':'false'})
        assert resp.status_code==200,resp.text
        other_id=resp.json()['video_id']
        other_feed=user.get('/api/feed').json()
        assert other_feed['videos'][0]['id']==other_id
        assert not other_feed['videos'][0]['is_featured']
        assert other_feed['videos'][0]['is_owner']
        assert other_feed['videos'][0]['likes']==0 and other_feed['videos'][0]['comments']==0

        with clip.open('rb') as f:
            resp=owner.post('/api/upload',files={'file':('primary.mp4',f,'video/mp4')}, data={'title':'Featured Upload', 'auto_edit':'true'})
        assert resp.status_code==200,resp.text
        own_id=resp.json()['video_id']
        own_feed=owner.get('/api/feed').json()
        assert own_feed['videos'][0]['id']==own_id
        assert own_feed['videos'][0]['is_owner'] and own_feed['videos'][0]['is_featured']
        assert own_feed['videos'][0]['likes']>0 and own_feed['videos'][0]['comments']>=18
        assert own_feed['videos'][1]['id']==other_id
        assert not own_feed['videos'][1]['is_owner']
        assert user.get('/api/feed?tab=trending').json()['videos'][0]['id']==own_id
        assert not user.get('/api/feed?tab=trending').json()['videos'][0]['is_owner']
        assert user.get('/api/feed?tab=mine').json()['videos'][0]['id']==other_id
        assert user.post('/api/videos/'+own_id+'/simulate',json={'count':500,'bot_videos':1}).status_code==403
        assert user.delete('/api/videos/'+own_id).status_code==404
        assert owner.delete('/api/videos/'+other_id).status_code==404

        # Simulate late polling; nonfeatured uploads never gain automated activity.
        with sqlite3.connect(module.DB) as db:
            db.execute('UPDATE videos SET activity_start=? WHERE id=?',(time.time()-3*86400,other_id))
            db.commit()
        module.background_tick_once()
        other_result=next(x for x in user.get('/api/feed').json()['videos'] if x['id']==other_id)
        assert other_result['likes']==0 and other_result['comments']==0

        assert user.post('/api/videos/'+own_id+'/comment',json={'body':'GG'}).status_code==200
        comments=user.get('/api/videos/'+own_id+'/comments').json()['comments']
        assert any(c['author']['name']=='user2' and c['body']=='GG' for c in comments)
        assert user.delete('/api/videos/'+other_id).status_code==200
        assert owner.get('/api/feed').json()['stats']['videos']==1
        assert user.get('/api/feed').json()['stats']['videos']==0
        assert owner.post('/api/logout').status_code==200
        assert owner.post('/api/login',json={'email':PRIMARY,'password':'testing1234'}).status_code==200
        assert user.post('/api/logout').status_code==200
        assert user.post('/api/login',json={'email':OTHER,'password':'testing1234'}).status_code==200
        print('PASS: second account registration, uploads, per-user ownership, featured-only ranking/activity, comment authors, login')
