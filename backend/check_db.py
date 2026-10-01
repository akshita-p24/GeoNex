import asyncio
import sys
from sqlalchemy import text
from app.core.database import AsyncSessionLocal, check_db_connection

async def main():
    conn_info = await check_db_connection()
    print("CONNECTION INFO:", conn_info)
    
    async with AsyncSessionLocal() as session:
        # Check public tables
        res = await session.execute(text("SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY table_name;"))
        tables = [r[0] for r in res.fetchall()]
        print("PUBLIC TABLES:", tables)
        
        # Check users count
        if "users" in tables:
            u_res = await session.execute(text("SELECT email, role, full_name FROM users;"))
            users = u_res.fetchall()
            print(f"USERS ({len(users)}):", [(u[0], u[1], u[2]) for u in users])
        else:
            print("users table does not exist!")

if __name__ == "__main__":
    asyncio.run(main())
