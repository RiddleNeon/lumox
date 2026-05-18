# Implemented Features

> [!NOTE]
> 
> I collapsed the screenshots into sections below the text. you can view the screenshots by expanding the sections!


### Core Features
- [x] User Authentication
- [x] Functional Supabase Backend
- [x] Video Feed
- [x] Comments
- [x] Likes
- [x] User Profiles
- [x] Followers and Following
- [x] Advanced Search Functionality
- [x] Direct Messaging
- [x] AI-Chatbots
- [x] User moderation tools

### Video & Content
- [x] Video tags
- [x] YouTube channel integration
- [x] YouTube video player integration
- [x] Basic recommendation algorithm



### Quest System
- [x] Quest screen for connecting categories
- [x] Quest managing system
- [x] Quest version control system
- [x] Dynamic quest colors
- [x] Auto-Layouting of quests

### Dictionary
- [x] Dictionary screen for managing terms and definitions
- [x] automatic linking of terms to their corresponding dictionary entries
- [x] Quick access to dictionary entries in chat conversations



### Engagement
- [x] Streaks
- [x] Daily goals


### Customization & Themes
- [x] Profile Customisation
- [x] Themes
- [x] Theme generation system
- [x] Community theme marketplace

---

## Videos

I've implemented two different video feed and player types: a general video feed and a YouTube video feed.

### General Video Player

The general video player can show every video that has a specified URL that contains the video data. Normally those links end with `.mp4`, `.webm`, or `.ogg`.

### YouTube Video Player

YouTube videos are special. They don't provide direct links to the video data. That's why you need to use an embedded player that shows the video using an IFrame.

These IFrames are a bit more difficult to work with, because the YouTube IFrame API has a lot of rate limits and restrictions.

For example:
- It only allows you to play one video with autoplay at a time
- You have to carefully dispose of the IFrame when switching videos
- You can't preload YouTube videos
- Videos must load when scrolled into view

<details>
  <summary>Screenshot: General / YouTube video player</summary>

  ![Screenshot from 2026-05-18 22-06-24](https://github.com/user-attachments/assets/f23d0605-b820-4e74-b259-15f16176555d)
</details>

---

## Comments

The videos can be commented on. You can also like comments and reply to them.

<details>
  <summary>Screenshot: Comments</summary>

  ![image](https://github.com/user-attachments/assets/ea722f5c-a4f3-473a-b24a-7517c188f10d)
</details>

---

## User Profiles

Users have their own profiles where they can see:
- Their videos
- Liked videos
- Followers
- Following users

The profile also shows:
- User bio
- Profile picture
- Total published videos
- Total received likes
- Username and display name

<details>
  <summary>Screenshot: User profile</summary>

  ![Screenshot from 2026-05-18 21-59-04](https://github.com/user-attachments/assets/bf372032-29b4-497a-a8d4-d9581a73546c)
</details>

---

## Advanced Search Functionality

Users can search for videos, users, and tags using the search bar.

The search results are calculated using an advanced search algorithm that uses:
- Video title
- Description
- Tags
- Popularity

to determine the relevance of the search results.

<details>
  <summary>Screenshot: Advanced search</summary>

  ![Screenshot from 2026-05-18 22-00-57](https://github.com/user-attachments/assets/f3953a18-c507-4faf-a12f-1b54400716c3)
</details>

---

## Direct Messaging

Users can send direct messages to each other. They can:
- Send text messages
- Share videos
- Edit & Delete Messages
- View Editing history if they are admins

Technically, it also supports group chats, but this is not implemented in the frontend yet.

<details>
  <summary>Screenshot: Direct messaging</summary>

  ![image](https://github.com/user-attachments/assets/805af753-3ad8-4505-a727-d39d4f6a1040)
</details>

## AI-Chatbots
Users can chat with AI-Chatbots that are trained on specific topics. The answers are generated in the backend and only accessable to pro users. You can request access to the AI-Chatbots in the settings in the advanced tab.

<details>
  <summary>Screenshot: AI-Chatbots</summary>

  ![image](https://github.com/user-attachments/assets/59f1a4e2-3a25-4568-85cd-bd40196f1400)
</details>

---

## Profile Customisation

Users can customize their profiles by changing their:
- Profile picture
- Display name
- Username
- Bio

<details>
  <summary>Screenshot: Profile customisation</summary>

  ![image](https://github.com/user-attachments/assets/29b53644-7968-4b1f-a08d-d76eedcee2cb)
</details>

---

## Themes

Users can choose between different themes for the platform. They can import/export their themes as JSON files or share them with the community.

<details>
  <summary>Screenshot: Themes</summary>

  ![image](https://github.com/user-attachments/assets/677d17e1-77fc-48cc-ba2e-8f24c7f69294)
</details>


### Theme Generation System

The theme generation system allows users to create their own themes by selecting colors and styles for different elements of the platform. They can modify colors, border radius, border thickness, elevation, hues and more.

They can then save their themes and share them with the community.

<details>
  <summary>Screenshot: Theme generation</summary>

  ![image](https://github.com/user-attachments/assets/2f66ca33-db40-47f5-9af2-b7a153523dc9)
</details>


### Community Theme Marketplace

The community theme marketplace allows users to:
- Share their themes
- Browse available themes
- Import themes to their profiles
- Like themes
- Remix themes

Remixing means taking an existing theme, modifying it, and publishing it as a new theme.

<details>
  <summary>Screenshot: Theme marketplace</summary>

  ![image](https://github.com/user-attachments/assets/edc652d5-b9b3-4e02-abdc-a48b824a5272)
</details>

---

## Quests

Different topics are represented as "Quests", inspired by similar systems in games.

Quests can:
- Have prerequisites
- Be connected to other quests
- Represent learning dependencies

Example:
"Multiplication" can be a prerequisite for "Division".

Each quest has:
- A color
- A description

Connections may also have level requirements, meaning a quest must be completed multiple times before unlocking the next one.

<details>
  <summary>Screenshot: Quest example</summary>

  ![image](https://github.com/user-attachments/assets/f588ad6d-7874-4f3b-8296-8a095f655e30)
</details>

---

### Quest Managing System

Users can:
- Create quests
- Edit quests
- Delete quests
- Connect quests via prerequisites

//todo screenshot
<details>
  <summary>Screenshot: Quest managing system (todo)</summary>

  ![image](https://github.com/user-attachments/assets/2064363a-867e-4970-8493-c792833f7dc2)
</details>

---

### Quest Version Control System

After making changes, users can publish them.

Features:
- Every change since the last publish is stored
- Ability to revert to previous versions
- Only changed data is stored
- Individual changes can be removed before publishing
- Changes are merged into a new version

Users can name each change to track what was modified and why.

There is also a feature that suggests names automatically based on the changes (e.g. "Changed color to teal").

<details>
  <summary>Screenshots: Quest version control</summary>

  ![image](https://github.com/user-attachments/assets/82c1608c-065d-430b-9489-3b5b6b876fa7) &nbsp;&nbsp;&nbsp;
  ![image](https://github.com/user-attachments/assets/f109f991-fa90-4a55-8727-ad473141e1b6)
</details>

---

### Dynamic Quest Colors

Quests can have either static or dynamic colors.

Dynamic colors are calculated based on connected quests.

Example:
- Red + Blue prerequisites → Purple quest

This helps to:
- Visualize relationships between topics
- Create a consistent color scheme
- Generate gradients across the quest map

<details>
  <summary>Screenshot: Dynamic quest colors</summary>

  ![image](https://github.com/user-attachments/assets/34346742-5d37-4e29-b36d-50d3baac4998)
</details>

---

### Auto-Layouting of Quests
In debug mode you can auto-layout the quests. This means that the quests will be automatically arranged based on their connections.
This is especially useful for large quest maps, where manual arrangement would be difficult. It consists of a force-directed graph algorithm that calculates the optimal position for each quest based on its connections and the positions of other quests. 
After that it uses a grid-based system to snap the quests into place and avoid overlaps. To make it look more natural, a physics-based force simulation is applied, that pushes quests apart if they are too close and pulls them together if they are too far away. 
The result is a well-organized and visually appealing quest map that clearly shows the relationships between different topics.

<details>
  <summary>Screenshot: Auto-layouting of quests</summary>

  ![Screenshot from 2026-05-18 22-16-18](https://github.com/user-attachments/assets/d10cd90f-5083-4c02-84f5-26eca6d4feeb)
</details>

---

## Dictionary
Since you often stumble upon new terms while learning, I implemented a dictionary feature that allows users to look up definitions and explanations for various terms.
Basically these dictionary entries are just the quests and their descriptions as definitions. Additionally, since every term has a corresponding quest, you can 
go to the quest tree and view the topic with its context and prerequisites, which is often more helpful than a simple definition.

### Dictionary Screen
The dictionary screen allows users to see all the terms and definitions in a list. They can also search for specific terms and filter them by category.

<details>
  <summary>Screenshot: Dictionary screen</summary>

  ![image](https://github.com/user-attachments/assets/f6230f83-9709-404d-b9a5-4659b974cd43)
</details>


### Automatic Linking of Terms
Whenever a term is mentioned in a video description, comment, or chat conversation, it is automatically linked to its corresponding dictionary entry. This allows users to quickly access the definition and related information about the term without having to leave the current context.
So if you see a term you don't understand and its underlined, you can just click on it and view the definition or go to the quest tree.

<details>
  <summary>Screenshot: Automatic linking of terms</summary>

  ![image](https://github.com/user-attachments/assets/094b6ee5-c3ac-4d82-9f68-b2c8ce7b5441)
</details>



---

## User Moderation Tools

Users can report other users if they find them inappropriate. Additionally if a user uses inappropriate language in their videos, comments, or chat messages, they can be automatically flagged by the system and receive a warning. If a user receives too many reports the user is banned.
The banned user can Appeal the ban and moderators then review the case and decide whether to lift the ban. Since i currently don't have a moderation team, the appeals are automatically accepted and the user is unbanned after a few seconds.

<details>
  <summary>Screenshot: User moderation tools</summary>

  ![image](https://github.com/user-attachments/assets/6d91587a-943e-4186-8c76-4f8d277c7241)
</details>


---

## Daily Goals

Every day, users receive a new goal that encourages interaction with the platform.

Examples:
- Watch 30 videos
- Like 5 comments

Additional dynamic homepage cards include:
- Continue Watching
- Recommended for You

<details>
  <summary>Screenshot: Daily goals</summary>

  ![image](https://github.com/user-attachments/assets/d3cd463e-a31f-46cf-9021-5a4b66426216)
</details>

---

## Home Page

The home page includes:
- Streaks (number of consecutive days the user has used the app)
- Daily goals
- Discover section (new content)
- Following section (latest content from followed users)
- Continue Watching section (videos that were started but not finished)

<details>
  <summary>Screenshot: Home page 1</summary>

  ![image](https://github.com/user-attachments/assets/ac6646fa-4ee3-4f35-b006-d6bef2dfc58e)
</details>

<details>
  <summary>Screenshot: Home page 2</summary>

  ![image](https://github.com/user-attachments/assets/5bc5a9c3-94c6-41a3-8d4d-9faa7f99a724)
</details>

---

## Easter Eggs

I added some Easter Eggs to the platform. Can you find them all?
