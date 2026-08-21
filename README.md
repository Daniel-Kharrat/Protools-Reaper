# Daniel Kharrat's Reaper-Protools Configuration

## How to Install
🔻Watch the video🔻

[<img src="MISC%20Data/Daniel_Splash%20Screen.jpg" width="165" alt="Watch the video">](https://youtu.be/7FLHFj_httw)

### Step 0:
Install Reapack and the SWS Extensions for reaper if you haven't already
### Step 1:
Download latest version from the ***Configurations*** folder above

In Reaper go to: **Options → Preferences**

Under **General settings** click on **"Import configuration..."**

Find the file you just downloaded and click **"Open"** then **"Import"** (⚠️this will overwrite your existing config⚠️)

### Step 2:
Go to: **Extensions → ReaPack → Manage repositories...** 

Double click on **Daniel Kharrat**

Click on **Install/update Daniel Kharrat → Install all packages in this repository**

Also install the **ReaTeam Extensions** in the same manner

After all the required packages finish installing, restart reaper and you'll be ready to go

For future updates you can go to: **Extensions → ReaPack → Synchronize packages**

### Step 3:
You may need to do some tweaks on different computers

1) if the track in the mixer window becomes smaller when you arm it you need to go to:

**Extensions → SWS/S&M → Auto Color/Icon/Layout...**

in the **MCP Layout** column, right click and choose the appropriate size for each track color (100%, 150%, 200%)


2) to get my custom Splash Screen when you launch reaper go to: **Options → Preferences**

Under **General settings** click on **"Advanced UI/system tweaks..."** on the bottom of the page

Under **Custom splash screen image:** click ***Browse...*** and select my custom image

(you will find it in the ColorThemes folder inside the REAPER resource path)


3) Replace toolbar icons to have the correct blue color instead of green

Go to: **Extensions → ReaPack → Manage repositories...** 

Double click on **Daniel Kharrat** and click on the hyperlink (it will download them automatically)

go to your downloads folder, unzip the toolbar_icons folder

go to the REAPER resource folder → Data folder

replace the toolbar icons folder with the new one and restart reaper


4) on mac change the shortcut for spotlight search because we're using cmd + space to record

go to System Settings... → Keyboard → Keyboard Shortcuts... → Spotlight

change the shortcut for **Show Spotlight search** to something else




## If you wish to install some of the Scripts or FX without my config
You can copy the repository link from here:

```
https://github.com/Daniel-Kharrat/Protools-Reaper/raw/refs/heads/master/index.xml
```

Go to: **REAPER → Extensions → ReaPack → Import repositories…**

Paste it there and click OK, then go to:


**REAPER → Extensions → ReaPack → Manage repositories…**

Double click on **Daniel Kharrat** then click on **Install/update Daniel Kharrat → Install individual packages in this repository**
