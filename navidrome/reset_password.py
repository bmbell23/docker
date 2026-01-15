#!/usr/bin/env python3
"""
Reset Navidrome user password by updating the database directly.
"""
import sqlite3
import bcrypt
import sys

def reset_password(db_path, username, new_password):
    """Reset password for a user in the Navidrome database."""
    # Generate bcrypt hash
    password_hash = bcrypt.hashpw(new_password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    
    # Connect to database
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Update password
    cursor.execute("UPDATE user SET password = ? WHERE user_name = ?", (password_hash, username))
    
    if cursor.rowcount == 0:
        print(f"Error: User '{username}' not found")
        conn.close()
        return False
    
    conn.commit()
    conn.close()
    print(f"Password successfully reset for user '{username}'")
    return True

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python3 reset_password.py <db_path> <username> <new_password>")
        sys.exit(1)
    
    db_path = sys.argv[1]
    username = sys.argv[2]
    new_password = sys.argv[3]
    
    if not reset_password(db_path, username, new_password):
        sys.exit(1)

