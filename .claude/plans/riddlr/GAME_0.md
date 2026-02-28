<!-- start context -->

We are creating a Elixir/Phoenix-based game together. It might be called cyrptogram, riddler or similar. The game mechanics are as follows:

- a game admin can create a riddle in a secure, authenticated back-end system that only admins have access to
- each riddle that is created will be a phrase or a few sentences. It is always a play on words that can have one or many acceptable answers.
- players compete in real time to complete a riddle once it is made live
- players can see in real time how many other players are online
- each player can sign up/register (phx.gen.auth) or connect their account using openid connect. they must create a username and verify their account via SMS or email. players can be banned by admins for bad behaviour or foul language
- when a game live_date is set, players can be informed of when the game will start via sms or email
- when a game is in :live state, it can be played by one or more players
- each game has a solve time: the amount of time contestants have to complete it
- the player that solves the riddle first is the winner
- a game win earns a player 10 points; second place gets 7 points and third place gets 3 points. every other player receives 0 points
- a player can answer as many times as they like within the solve time. when the solve time is met, the game ends for all players
- after a player correctly solves the riddle, they cannot submit any further answers
- the UI of the game is simple: there is a block of text that asks the riddle and each contestant sees a simple text input where they can submit their answer
- answers from all players are show in realtime (live view) in the order they come in, with the players name presented beside the reponse and the number of seconds after the game was set to live beside the answer (millisecond precision)
- there will be leaderboards displaying players achievemnts
- after a guess is made, the system will check that the response is not racist, inflammatory, etc.. if it is, it gets hidden from view

- a riddle schema could look like this:

```
- name: string, the name of the riddle
- description: text, the text that makes up the riddle
- publish_status: enum <:draft, :published, :archived>, default: :draft, the statis of the riddle
- live_date: utc datetime, the date/time that the game will be available to play
- play_status: enum <:closed, :ready, :live, :ended>, default: :closed, the current status of the riddle
- solve_time: integer (seconds), the time allowed to solve the riddle, default: 120
- answers: string array, a list of acceptable answers for the riddle, default: empty
- each riddle has a winner (player)
```

- a users/player schema could look like this:

```
- username: string <required>, the player username, must be unique
- email_address: string <optional>, the player email address, must be unique
- mobile_number: string <optional>, the player's mobile number, used for sms messaging
- communication_preference: enum<:email, :sms>, default: email
- account_status: enum<:active, :inactive, :banned>, default: :active
- each player can win one or more riddle challenges (they can have many victories)
- players can have a email_address. mobile_number or both. admins can ban players
```

<!-- end context -->

<!-- start task -->

Consider all of the above and provide a high level plan of how you would organise this game as a Phoenix project. Key to this game is: building anticipation among players, keeping players addictied to the thrill of winning, and the realtime experience. Leaderboards are also important.

<!-- end task -->

<!-- 2. plan next steps -->

- auth/login depends on tgam cookie (or other for testing)
- open id connect etc. a option but not necessary. add login w snapchat?
- use email for weekly (?) game schedules

- add to riddle schema: add :credit str for custom creator names, consider %Creator{} in future

- admin profiles - highlight games editor
- allow registered users to create a riddlr game

- "subtext" project? "what's underneath the surface of how your teams work with AI. Clever media nod, slightly mysterious." "sage"?
  ** work: agent to put together md files? how do teams manage their**
  **how do we share this knowledge? more than prompt library
  **search saved prompts by department\*\*
