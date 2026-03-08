import time
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service

options = Options()
options.add_argument("--headless")
options.add_argument("--disable-gpu")
options.add_argument("--no-sandbox")

# Enable logging
options.set_capability("goog:loggingPrefs", {"browser": "ALL"})

try:
    print("Starting Chrome...")
    driver = webdriver.Chrome(options=options)
    print("Loading page...")
    driver.get("http://localhost:8080")
    
    # Wait for Flutter to attempt to initialize
    time.sleep(3)
    
    print("--- BROWSER CONSOLE LOGS ---")
    for log in driver.get_log("browser"):
        print(f"[{log['level']}] {log['message']}")
    print("----------------------------")
    
    driver.quit()
    print("Done.")
except Exception as e:
    print(f"Selenium error: {e}")
