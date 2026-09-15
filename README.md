# Daniel Kharrat's Reaper-Protools Configuration

## How to Install
🔻Watch the video🔻

[<img src="MISC%20Data/Daniel_Splash%20Screen.jpg" width="165" alt="Watch the video">](https://youtu.be/CJbhZe4WvC8)

### Step 0:
Install [Reapack](https://reapack.com/) if you haven't already:

In Reaper go to: **Options → Show REAPER resource path in Explorer/finder...**

Look for a folder called **UserPlugins** and put the reapack file in it

### Step 1:
Download the latest [Configuration v3.7](https://github.com/Daniel-Kharrat/Protools-Reaper/raw/refs/heads/master/Configurations/Daniel_Reaper_Protools%20v3.7.ReaperConfigZip)

In Reaper go to: **Options → Preferences**

Under **General settings** click on **"Import configuration..."**

Find the file you just downloaded and click **"Open"** then **"Import"** (⚠️this will overwrite your existing config⚠️)

### Step 2:
Go to: **Extensions → ReaPack → Synchronize packages** 

(it will install **Daniel Kharrat** and **ReaTeam Extensions**)

After both repositories finish installing, **RESTART** reaper and you'll be ready to go


## You may need to do some tweaks on different computers

1) If the track in the mixer window becomes smaller when you arm it you need to go to:

**Extensions → SWS/S&M → Auto Color/Icon/Layout...**

in the **MCP Layout** column, right click and choose the appropriate size for each track color (100%, 150%, 200%)


2) To get my custom Splash Screen when you launch reaper

open the actions list and run the script called: **Daniel_Set splash screen.lua**


3) Replace toolbar icons if you're using my theme

open the actions list and run the script called: **Daniel_Replace toolbar_icons.lua**


4) On mac change the shortcut for spotlight search because we're using cmd + space to record

go to System Settings... → Keyboard → Keyboard Shortcuts... → Spotlight

change the shortcut for ***Show Spotlight search*** to "opt + space"

change the shortcut for ***Show Finder search window*** to "opt + cmd + space"


## For future Updates
1) run the script called: **Daniel_Save personal settings.lua**

2) import the new config file

3) run the script called: **Daniel_Restore personal settings.lua**

4) update the scripts by going to: **Extensions → ReaPack → Manage repositories...**

Double click on **Daniel Kharrat**

Click on **Install/update Daniel Kharrat → Install all packages in this repository**

5) If you reinstall the REAPER program itself it will overwrite the toolbar icons to the default green

so you'll have to replace them with my icons again by going to the actions list and run the script called:

**Daniel_Replace toolbar_icons.lua**


## If you wish to install some of the Scripts or FX without my config
You can copy the repository link from here:

```
https://github.com/Daniel-Kharrat/Protools-Reaper/raw/refs/heads/master/index.xml
```

In Reaper go to: **Extensions → ReaPack → Import repositories…**

Paste it there and click OK, then go to:

**Extensions → ReaPack → Manage repositories…**

Double click on **Daniel Kharrat** then click on:

**Install/update Daniel Kharrat → Install individual packages in this repository**
