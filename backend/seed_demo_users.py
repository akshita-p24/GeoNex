import asyncio
from sqlalchemy import select
from app.core.database import AsyncSessionLocal
from app.core.security import hash_password
from app.models.user import User, UserRole

DEMO_USERS = [
    {
        "email": "admin@geonex.in",
        "full_name": "SDMA Administrator",
        "password": "admin1234",
        "role": UserRole.ADMIN,
    },
    {
        "email": "officer@geonex.in",
        "full_name": "Field Officer NER",
        "password": "officer1234",
        "role": UserRole.FIELD_OFFICER,
    },
    {
        "email": "citizen@geonex.in",
        "full_name": "Citizen Reporter",
        "password": "citizen1234",
        "role": UserRole.CITIZEN,
    },
]

async def seed():
    async with AsyncSessionLocal() as session:
        for u_data in DEMO_USERS:
            stmt = select(User).where(User.email == u_data["email"])
            res = await session.execute(stmt)
            existing = res.scalar_one_or_none()
            if not existing:
                user = User(
                    email=u_data["email"],
                    full_name=u_data["full_name"],
                    hashed_password=hash_password(u_data["password"]),
                    role=u_data["role"],
                    is_active=True,
                )
                session.add(user)
                print(f"Creating user {u_data['email']} ({u_data['role'].value})...")
            else:
                existing.hashed_password = hash_password(u_data["password"])
                existing.role = u_data["role"]
                existing.is_active = True
                print(f"Updating user {u_data['email']} password and role ({u_data['role'].value})...")
        await session.commit()
        print("Demo users seeded successfully.")

if __name__ == "__main__":
    asyncio.run(seed())
