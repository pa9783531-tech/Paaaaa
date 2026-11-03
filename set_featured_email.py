"""Move an existing PakesY private owner account to the new featured email.

Run with the local PakesY server stopped. This requires the existing password
and preserves previously uploaded videos and statistics.
"""
from getpass import getpass
import hmac
import sys
from app import connect, FEATURED_EMAIL, hash_password


def main():
    with connect() as db:
        old = db.execute('SELECT email,salt,password_hash FROM owner WHERE id=1').fetchone()
    if not old:
        print('No owner account exists yet. Register from the website using:', FEATURED_EMAIL)
        return 0
    if old['email'] == FEATURED_EMAIL:
        print('The featured email is already active:', FEATURED_EMAIL)
        return 0

    print('Current local account:', old['email'])
    password = getpass('Enter the CURRENT account password: ')
    entered = hash_password(password, old['salt'])
    if not hmac.compare_digest(entered, old['password_hash']):
        print('Incorrect password. No changes were made.')
        return 1

    with connect() as db:
        if db.execute('SELECT 1 FROM users WHERE email=?', (FEATURED_EMAIL,)).fetchone():
            print('The new email is already registered. No changes were made.')
            return 1
        db.execute('UPDATE owner SET email=? WHERE id=1 AND email=?', (FEATURED_EMAIL, old['email']))
        db.execute('UPDATE users SET email=? WHERE email=?', (FEATURED_EMAIL, old['email']))
        db.execute('UPDATE videos SET uploader_email=? WHERE actor_id=0 AND uploader_email=?', (FEATURED_EMAIL, old['email']))
        db.execute('UPDATE comments SET commenter_email=? WHERE actor_id=0 AND commenter_email=?', (FEATURED_EMAIL, old['email']))
    print('Account updated to:', FEATURED_EMAIL)
    print('Your existing password is unchanged. Sign in again after restarting the server.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
