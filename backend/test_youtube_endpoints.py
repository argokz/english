import sys
import asyncio
import httpx
from colorama import init, Fore

init()

BASE_URL = "http://localhost:8000"

async def test_process():
    print(f"\n{Fore.GREEN}Testing /youtube/process (Auto-search IELTS)...{Fore.RESET}")
    async with httpx.AsyncClient() as client:
        # First login or just call directly if endpoints are open
        # Assuming we need auth, let's login first
        print(f"Login as admin...")
        login_res = await client.post(
            f"{BASE_URL}/api/v1/auth/login", 
            data={"username": "dankokz@gmail.com", "password": "securepassword"}
        )
        if login_res.status_code != 200:
            print(f"{Fore.RED}Login failed: {login_res.text}{Fore.RESET}")
            return None
            
        token = login_res.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}
        
        # Test process
        res = await client.post(
            f"{BASE_URL}/api/v1/youtube/process", 
            json={"url": "", "target_lang": "ru"},
            headers=headers,
            timeout=60.0
        )
        print(f"Status: {res.status_code}")
        if res.status_code == 200:
            data = res.json()
            print(f"Success! Video ID: {data['video_id']}")
            print(f"URL: {data['url']}")
            return data, headers
        else:
            print(f"{Fore.RED}Failed: {res.text}{Fore.RESET}")
            return None, headers

async def test_questions(video_id_uuid, headers):
    print(f"\n{Fore.GREEN}Testing /youtube/{{id}}/questions...{Fore.RESET}")
    async with httpx.AsyncClient() as client:
        res = await client.post(
            f"{BASE_URL}/api/v1/youtube/{video_id_uuid}/questions", 
            headers=headers,
            timeout=60.0
        )
        print(f"Status: {res.status_code}")
        if res.status_code == 200:
            print(f"Questions JSON:")
            print(res.json())
        else:
            print(f"{Fore.RED}Failed: {res.text}{Fore.RESET}")

async def test_history(headers):
    print(f"\n{Fore.GREEN}Testing /youtube/history...{Fore.RESET}")
    async with httpx.AsyncClient() as client:
        res = await client.get(
            f"{BASE_URL}/api/v1/youtube/history", 
            headers=headers
        )
        print(f"Status: {res.status_code}")
        if res.status_code == 200:
            data = res.json()
            print(f"Found {len(data)} history items")
        else:
            print(f"{Fore.RED}Failed: {res.text}{Fore.RESET}")

async def main():
    result = await test_process()
    if result and result[0]:
        data, headers = result
        await test_history(headers)
        await test_questions(data["id"], headers)

if __name__ == "__main__":
    asyncio.run(main())
