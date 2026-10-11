"""
init_db.py - Initialize database with first platform admin user

Run this after setting up the database schema to create your first admin user.
"""

import os
import sys
from getpass import getpass
from dotenv import load_dotenv

load_dotenv()

# Import after load_dotenv to ensure env vars are available
from database.database import UserDB, DatabaseConnection
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def create_platform_admin():
    """Create the first platform admin user"""
    print("="*60)
    print("Pre-Consultation System - Platform Admin Setup")
    print("="*60)
    print()
    
    # Initialize database connection
    try:
        DatabaseConnection.initialize_pool()
        print("✅ Database connected")
    except Exception as e:
        print(f"❌ Database connection failed: {e}")
        print("\nPlease ensure:")
        print("1. PostgreSQL is running")
        print("2. Database exists (create with: CREATE DATABASE pre_consultation_db;)")
        print("3. Schema is loaded (run: psql -f database/schema.sql)")
        print("4. .env file has correct DB_* variables")
        sys.exit(1)
    
    print()
    print("Create your platform admin account:")
    print()
    
    # Get user input
    email = input("Email: ").strip()
    if not email or '@' not in email:
        print("❌ Invalid email address")
        sys.exit(1)
    
    # Check if user already exists
    existing = UserDB.get_user_by_email(email)
    if existing:
        print(f"❌ User with email {email} already exists")
        sys.exit(1)
    
    full_name = input("Full Name: ").strip()
    if not full_name:
        print("❌ Full name is required")
        sys.exit(1)
    
    password = getpass("Password: ")
    password_confirm = getpass("Confirm Password: ")
    
    if password != password_confirm:
        print("❌ Passwords do not match")
        sys.exit(1)
    
    if len(password) < 8:
        print("❌ Password must be at least 8 characters")
        sys.exit(1)
    
    # Create user
    try:
        hashed = pwd_context.hash(password)
        user = UserDB.create_user(
            email=email,
            password_hash=hashed,
            full_name=full_name,
            role='platform_admin',
            facility_id=None
        )
        
        print()
        print("="*60)
        print("✅ Platform admin created successfully!")
        print("="*60)
        print(f"User ID: {user['user_id']}")
        print(f"Email: {user['email']}")
        print(f"Name: {user['full_name']}")
        print(f"Role: {user['role']}")
        print()
        print("You can now login at: http://localhost:8000/auth/login")
        print()
        
    except Exception as e:
        print(f"❌ Failed to create user: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    
    finally:
        DatabaseConnection.close_pool()


if __name__ == "__main__":
    create_platform_admin()
