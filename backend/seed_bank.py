import asyncio
import httpx
import argparse
import sys
from colorama import init, Fore

init()

BASE_URL = "http://localhost:8000"

async def seed_bank(count: int, base_url: str):
    """
    Script to call the /youtube/exam/bank/seed endpoint.
    """
    print(f"\n{Fore.CYAN}🚀 Starting Exam Bank Seeding...{Fore.RESET}")
    
    async with httpx.AsyncClient() as client:
        # No auth needed for this endpoint in dev
        url = f"{base_url}/youtube/exam/bank/seed?count={count}"
        print(f"Calling seeding endpoint: {url}")
        
        try:
            res = await client.post(url, timeout=10.0)
            
            if res.status_code == 200:
                print(f"{Fore.GREEN}Success! {res.json()['message']}{Fore.RESET}")
                print(f"The server is now processing videos in the background.")
                print(f"Check the server logs to see the progress.")
            else:
                print(f"{Fore.RED}Failed to trigger seeding (Status {res.status_code}): {res.text}{Fore.RESET}")

        except Exception as e:
            print(f"{Fore.RED}An error occurred: {str(e)}{Fore.RESET}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Seed the IELTS Exam Bank")
    parser.add_argument("--count", type=int, default=5, help="Number of variants to generate per part (1-4)")
    parser.add_argument("--port", type=int, default=8007, help="Backend server port")
    parser.add_argument("--host", type=str, default="localhost", help="Backend server host")
    
    args = parser.parse_args()
    base_url = f"http://{args.host}:{args.port}"
    
    asyncio.run(seed_bank(args.count, base_url))
