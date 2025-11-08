#!/usr/bin/env python3
"""List all available wheels in a GitHub release"""
import sys
import json
import urllib.request

def list_wheels(tag='v0.17.11'):
    url = f"https://api.github.com/repos/kimalive/pc-ble-driver-py/releases/tags/{tag}"
    
    try:
        with urllib.request.urlopen(url) as response:
            data = json.loads(response.read())
            
        print(f"Release: {data.get('name', tag)}")
        print(f"Tag: {tag}")
        print(f"Published: {data.get('published_at', 'Unknown')}")
        print()
        
        assets = data.get('assets', [])
        wheels = [a for a in assets if a['name'].endswith('.whl')]
        
        if not wheels:
            print("No wheels found in this release.")
            return
        
        print(f"Available wheels ({len(wheels)}):")
        print()
        
        for wheel in sorted(wheels, key=lambda x: x['name']):
            name = wheel['name']
            download_url = wheel['browser_download_url']
            size_mb = wheel['size'] / (1024 * 1024)
            
            # Parse wheel name
            parts = name.replace('.whl', '').split('-')
            if len(parts) >= 4:
                version = parts[1]
                python_tag = parts[2]
                platform = parts[3]
                
                print(f"  {name}")
                print(f"    Version: {version}")
                print(f"    Python: {python_tag}")
                print(f"    Platform: {platform}")
                print(f"    Size: {size_mb:.2f} MB")
                print(f"    URL: {download_url}")
                print()
        
        print("\nInstallation examples:")
        print("=" * 70)
        for wheel in wheels[:3]:  # Show first 3 as examples
            download_url = wheel['browser_download_url']
            print(f"pip install {download_url}")
        
    except urllib.error.HTTPError as e:
        print(f"Error: Could not fetch release {tag}")
        print(f"HTTP {e.code}: {e.reason}")
        if e.code == 404:
            print(f"\nRelease {tag} not found. Available releases:")
            try:
                releases_url = "https://api.github.com/repos/kimalive/pc-ble-driver-py/releases"
                with urllib.request.urlopen(releases_url) as r:
                    releases = json.loads(r.read())
                    for release in releases[:5]:
                        print(f"  - {release['tag_name']}: {release.get('name', 'No name')}")
            except:
                pass
    except Exception as e:
        print(f"Error: {e}")

if __name__ == '__main__':
    tag = sys.argv[1] if len(sys.argv) > 1 else 'v0.17.11'
    list_wheels(tag)
