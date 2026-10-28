# Seed riddles, loaded by priv/repo/seeds.exs.
#
# Each map names its category by `category`; seeds.exs looks up (or creates)
# the category and sets `category_id`. Every riddle starts as a draft.

[
  %{
    name: "The Keyboard",
    description:
      "What has keys but no locks, space but no room, and you can enter but can't go inside?",
    answers: ["keyboard", "a keyboard", "computer keyboard"],
    solve_time: 60,
    category: "what am i",
    difficulty: "easy",
    hint: "Think about something you use every day to type.",
    hint_delay: 30,
    publish_status: "draft"
  },
  %{
    name: "The Echo",
    description: "What can you hear but not see or touch, even though you control it?",
    answers: ["echo", "an echo"],
    solve_time: 90,
    category: "what am i",
    difficulty: "medium",
    hint: "It's something that bounces back to you.",
    hint_delay: 45,
    publish_status: "draft"
  },
  %{
    name: "The Light Switch",
    description:
      "I have cities, but no houses. I have mountains, but no trees. I have water, but no fish. What am I?",
    answers: ["map", "a map"],
    solve_time: 120,
    category: "what am i",
    difficulty: "medium",
    hint: "Think about representation, not reality.",
    hint_delay: 60,
    publish_status: "draft"
  },
  %{
    name: "The River",
    description:
      "What runs but never walks, has a mouth but never talks, has a bed but never sleeps?",
    answers: ["river", "a river", "stream"],
    solve_time: 90,
    category: "what am i",
    difficulty: "easy",
    hint: "It flows through the land.",
    hint_delay: 45,
    publish_status: "draft"
  },
  %{
    name: "The Future",
    description: "The more you take, the more you leave behind. What am I?",
    answers: ["footsteps", "steps", "footprints"],
    solve_time: 120,
    category: "logic",
    difficulty: "hard",
    hint: "Think about what you create as you move.",
    hint_delay: 60,
    publish_status: "draft"
  },
  %{
    name: "The Towel",
    description: "What gets wet while drying?",
    answers: ["a towel", "towel"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Cold",
    description: "What can you catch, but not throw?",
    answers: ["a cold", "cold"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "The Legs",
    description: "What has a bottom at the top?",
    answers: ["your legs", "legs"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Clock",
    description: "What has hands but cannot clap?",
    answers: ["a clock", "clock"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "Light",
    description: "What can fill a room but takes up no space?",
    answers: ["light"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Phone",
    description: "What asks no questions but must be answered?",
    answers: ["a phone", "phone"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "Three Generations",
    description:
      "Two fathers and two sons are in a car, yet there are only three people in the car. How?",
    answers: [
      "grandfather, father, and son",
      "grandfather, father and son",
      "grandfather father son"
    ],
    category: "logic",
    publish_status: "draft"
  },
  %{
    name: "Red Paint",
    description: "What is red and smells like blue paint?",
    answers: ["red paint"],
    category: "trick question",
    publish_status: "draft"
  },
  %{
    name: "The Bullet",
    description: "Why is a bullet like a tender glance?",
    answers: ["it pierces hearts", "pierces hearts", "because it pierces hearts"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "The Bed",
    description: "What has one head, one foot, and four legs?",
    answers: ["a bed", "bed"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "Soap",
    description: "What gets smaller every time it takes a bath?",
    answers: ["soap"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Tongue",
    description: "What tastes better than it smells?",
    answers: ["the tongue", "tongue"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "Ajar",
    description: "When is a door no longer a door?",
    answers: ["when it's ajar", "ajar", "when it is ajar"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "The Towel 2",
    description: "What gets wetter and wetter the more it dries?",
    answers: ["towel"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Calendar",
    description:
      "No matter how little or how much you use me, you change me every month. What am I?",
    answers: ["a calendar", "calendar"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Candle",
    description: "What gets shorter as it grows older?",
    answers: ["a candle", "candle"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Fence",
    description: "What runs around the whole yard without moving?",
    answers: ["fence"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Last Brick",
    description: "How many bricks does it take to complete a building made of brick?",
    answers: ["the last one", "last one"],
    category: "trick question",
    publish_status: "draft"
  },
  %{
    name: "Incorrectly",
    description: "What word in the dictionary is spelled incorrectly?",
    answers: ["incorrectly"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "Letter E",
    description: "What do you see once in June, twice in November, and not at all in May?",
    answers: ["the letter e", "e", "letter e"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "Stone",
    description: "What five-letter word has one left when two letters are removed?",
    answers: ["stone"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "Live",
    description:
      "Spelled forwards I'm what you do every day, spelled backward I'm something you hate. What am I?",
    answers: ["live"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "Letter M",
    description: "What occurs once in a minute, twice in a moment, and never in 1,000 years?",
    answers: ["the letter m", "m", "letter m"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "Letter W",
    description: "What is at the end of a rainbow?",
    answers: ["the letter w", "w", "letter w"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "The Rubber Band",
    description: "What kind of band never plays music?",
    answers: ["a rubber band", "rubber band"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "The Teapot",
    description: "What starts with T, ends with T, and has T in it?",
    answers: ["a teapot", "teapot"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "Spelling Cow",
    description: "How do you spell \"cow\" in 13 letters?",
    answers: ["see o double you"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "Silence",
    description: "What is so fragile that saying its name breaks it?",
    answers: ["silence"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "Noon",
    description:
      "What four-letter word can be written forward, backward, or upside down and can still be read from left to right?",
    answers: ["noon"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "Letter E 2",
    description:
      "It is the beginning of eternity, the end of time and space. It is the start of every end, the end of every place.",
    answers: ["the letter e", "e", "letter e"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "The Deck Of Cards",
    description: "What has 13 hearts but no other organs?",
    answers: ["a deck of cards", "deck of cards"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Sick Boat",
    description: "Where do you take a sick boat?",
    answers: ["dock-tor", "the dock-tor", "doctor", "the doctor", "dock"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "Queue",
    description:
      "What five-letter English word can be pronounced the same even with four of its letters removed?",
    answers: ["queue"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "Short",
    description: "What five-letter word becomes shorter when you add two letters to it?",
    answers: ["short"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "The Prisoner",
    description:
      "If you tell a lie, we will hang you and if you tell the truth, we will shoot you\". What did the prisoner say to save himself?",
    answers: ["you will hang me"],
    category: "logic",
    publish_status: "draft"
  },
  %{
    name: "The Envelope",
    description: "What begins with an \"e\" and only contains one letter?",
    answers: ["an envelope", "envelope"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "The Relationship",
    description: "What kind of ship has two mates but no captain?",
    answers: ["a relationship", "relationship"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "Swims",
    description:
      "What 5-letter word typed in all capital letters can be read the same upside down?",
    answers: ["swims"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "Middle Names",
    description: "What do Alexander the Great and Winnie the Pooh have in common?",
    answers: ["their middle names", "middle names", "middle name", "the"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "Letter R",
    description:
      "Two in a corner, one in a room, zero in a house, but one in a shelter. What am I?",
    answers: ["the letter r", "r", "letter r"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "The Electric Train",
    description: "If an electric train is traveling south, then which way is the smoke going?",
    answers: ["no smoke", "none", "there is no smoke"],
    category: "trick question",
    publish_status: "draft"
  },
  %{
    name: "The Dictionary",
    description: "Where is the only place where today comes before yesterday?",
    answers: ["the dictionary", "dictionary"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "The Yardstick",
    description: "What has three feet but cannot walk?",
    answers: ["a yardstick", "yardstick"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "Ani's Sisters",
    description:
      "Ani's mother has five daughters: Katie, Sophia, Maya, and Shirley. Who's the fifth daughter?",
    answers: ["ani"],
    category: "trick question",
    publish_status: "draft"
  },
  %{
    name: "Ton",
    description: "Forward I am heavy, but backward I am not. What am I?",
    answers: ["ton"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "Zero",
    description: "What's a single-digit number with no value?",
    answers: ["zero", "0"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "Twins Twice",
    description: "How many people is \"two pairs of twins twice\"?",
    answers: ["eight", "8"],
    category: "logic",
    publish_status: "draft"
  },
  %{
    name: "Dozens",
    description:
      "A word I know, six letters it contains, remove one letter and 12 remains. What is it?",
    answers: ["dozens"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "Company and Crowd",
    description: "If two's company, and three's a crowd, what are four and five?",
    answers: ["nine", "9"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "The Ducks",
    description:
      "There are two ducks in front of a duck, two ducks behind a duck and a duck in the middle. How many ducks are there?",
    answers: ["three ducks", "three", "3"],
    category: "logic",
    publish_status: "draft"
  },
  %{
    name: "Four Daughters",
    description:
      "Jane and John have four daughters. Each of their daughters has one brother. How many children do Jane and John have in total?",
    answers: ["five", "5"],
    category: "logic",
    publish_status: "draft"
  },
  %{
    name: "Nothing",
    description: "Poor people have it. Rich people need it. If you eat it you die. What is it?",
    answers: ["nothing"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Name",
    description: "What belongs to you but is used by everyone you meet?",
    answers: ["your name", "name"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Library",
    description: "What building has the most stories?",
    answers: ["a library", "library"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "The Comb",
    description: "What has many teeth but cannot bite?",
    answers: ["a comb", "comb"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "Darkness",
    description: "The more there is the less you see. What is it?",
    answers: ["darkness"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Secret",
    description: "What do you lose the moment you share it?",
    answers: ["a secret", "secret"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Match",
    description:
      "You enter a dark room that contains a match, kerosene lamp, candle, and fireplace. What should you light first?",
    answers: ["the match", "match"],
    category: "trick question",
    publish_status: "draft"
  },
  %{
    name: "The Left Hand",
    description: "What can you hold in your right hand, but never in your left hand?",
    answers: ["your left hand", "left hand"],
    category: "trick question",
    publish_status: "draft"
  },
  %{
    name: "Sleep",
    description:
      "I weaken all men for hours each day. I show you strange visions while you are away. I take you by night, by day take you back. None suffer to have me, but do from my lack. What am I?",
    answers: ["sleep"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Garbage Truck",
    description: "What has four wheels and flies?",
    answers: ["a garbage truck", "garbage truck"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "The Footprints",
    description: "The more you take, the more you leave behind. What am I?",
    answers: ["footprints"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Question",
    description: "What question can you never say yes to?",
    answers: ["are you asleep"],
    category: "trick question",
    publish_status: "draft"
  },
  %{
    name: "Age",
    description: "What goes up but never comes down?",
    answers: ["age"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Bald Man",
    description:
      "A man goes out in heavy rain with nothing to protect him from it. His hair doesn't get wet. How does he do that?",
    answers: ["he's bald"],
    category: "trick question",
    publish_status: "draft"
  },
  %{
    name: "The Boss",
    description:
      "A man and his boss have the same parents but are not siblings. How is this possible?",
    answers: ["he's self-employed"],
    category: "logic",
    publish_status: "draft"
  },
  %{
    name: "The Hole",
    description:
      "You have a barrel full of water. What do you add to the barrel to make it lighter?",
    answers: ["a hole", "hole"],
    category: "logic",
    publish_status: "draft"
  },
  %{
    name: "The Corn On The Cob",
    description:
      "Throw away the outside and cook the inside, then eat the outside and throw away the inside. What is it?",
    answers: ["corn on the cob"],
    category: "trick question",
    publish_status: "draft"
  },
  %{
    name: "The Carrot",
    description: "I'm orange, I wear a green hat and I sound like a parrot. What am I?",
    answers: ["a carrot", "carrot"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "Cutlery",
    description: "What do you buy to eat but never consume?",
    answers: ["cutlery"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "The Egg",
    description: "What must be broken before you can use it?",
    answers: ["egg"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "Breakfast",
    description: "What two things can you never eat for breakfast?",
    answers: ["lunch and dinner", "dinner and lunch"],
    category: "trick question",
    publish_status: "draft"
  },
  %{
    name: "The Egg 2",
    description: "What has to be broken before you can use it?",
    answers: ["an egg", "egg"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Potato",
    description: "What has lots of eyes, but can't see?",
    answers: ["a potato", "potato"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Mushroom",
    description: "What kind of room has no doors or windows?",
    answers: ["a mushroom", "mushroom"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "The Artichoke",
    description: "What has a heart that doesn't beat?",
    answers: ["artichoke"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "Root Beer",
    description: "How can kids drink beer and not get drunk?",
    answers: ["root beer", "by drinking root beer"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "Popcorn",
    description:
      "I make a loud sound when I'm changing. When I do change, I get bigger but weigh less. What am I?",
    answers: ["popcorn"],
    category: "trick question",
    publish_status: "draft"
  },
  %{
    name: "The Elephant",
    description: "What time is it when an elephant sits on a fence?",
    answers: ["time to fix the fence", "time to get a new fence"],
    category: "trick question",
    publish_status: "draft"
  },
  %{
    name: "The Cowboy",
    description:
      "A cowboy rides into town on Friday. He stays three days, then rides out of town on Friday. How?",
    answers: [
      "his horse is named friday",
      "horse is named friday",
      "horse named friday",
      "his horse"
    ],
    category: "trick question",
    publish_status: "draft"
  },
  %{
    name: "The Kitten",
    description: "I have a head like a cat and feet like a cat, but I am not a cat. What am I?",
    answers: ["a kitten", "kitten"],
    category: "trick question",
    publish_status: "draft"
  },
  %{
    name: "The Chicken",
    description: "What part of the chicken has the most feathers?",
    answers: ["the outside", "outside"],
    category: "trick question",
    publish_status: "draft"
  },
  %{
    name: "The Stamp",
    description: "What can travel all around the world without leaving its corner?",
    answers: ["a stamp", "stamp"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "Into the Woods",
    description: "How far can you walk into the woods?",
    answers: ["halfway", "half way"],
    category: "trick question",
    publish_status: "draft"
  },
  %{
    name: "The Map",
    description:
      "I have cities, but no houses. I have forests but no trees. I have water but no fish. What am I?",
    answers: ["a map", "map"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Pyramid",
    description:
      "Built for a king, my body guards him in death, not in life. I stand tall, pointing to the skies, yet I am not alive. What am I?",
    answers: ["a pyramid", "pyramid"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Statue",
    description:
      "Crafted in an ancient city, I am a testament to love and beauty, now found in a city of lights.",
    answers: ["venus de milo", "the venus de milo"],
    category: "unknown",
    publish_status: "draft"
  },
  %{
    name: "The Bank",
    description: "What has branches, but no fruit, trunk or leaves?",
    answers: ["a bank", "bank"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Coffin",
    description:
      "The person who makes it has no need of it; the person who buys it has no use for it. The person who uses it can neither see nor feel it. What is it?",
    answers: ["a coffin", "coffin"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "Time",
    description:
      "Until I am measured, I am not known. Yet how you miss me, when I have flown. What am I?",
    answers: ["time"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Piano",
    description: "What has many keys but cannot open a single lock?",
    answers: ["a piano", "piano"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Umbrella",
    description: "What can go up a chimney down, but can't go down a chimney up?",
    answers: ["an umbrella", "umbrella"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Wind",
    description: "What flies forever, rests never?",
    answers: ["the wind", "wind"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "Friday the 13th",
    description: "How many Friday the 13ths can there be in one calendar year?",
    answers: ["three", "3"],
    category: "logic",
    publish_status: "draft"
  },
  %{
    name: "Tulips",
    description: "What flowers are kissable?",
    answers: ["tulips"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "The Echo 2",
    description:
      "I speak without a mouth and listen without ears. I have no body, but I come alive with wind. What am I?",
    answers: ["an echo", "echo"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Breath",
    description:
      "What's lighter than a feather but impossible to hold for much more than a minute?",
    answers: ["your breath", "breath"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Stapler",
    description:
      "With pointed fangs I sit and wait; with piercing force I crunch out fate; grabbing victims, proclaiming might; physically joining with a single bite. What am I?",
    answers: ["a stapler", "stapler"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "Prison",
    description: "Where can you finish a book without finishing a sentence?",
    answers: ["prison"],
    category: "wordplay/pun",
    publish_status: "draft"
  },
  %{
    name: "The Three-Word Question",
    description: "What three-word question can you never answer \"yes\" to?",
    answers: ["are you dead"],
    category: "trick question",
    publish_status: "draft"
  },
  %{
    name: "The Parachute",
    description:
      "Two men are in a desert. They both have backpacks on. One of the guys is dead. The guy who is alive has his backpack open and the guy who is dead has his backpack closed. What is in the dead man's backpack?",
    answers: ["a parachute", "parachute"],
    category: "trick question",
    publish_status: "draft"
  },
  %{
    name: "Money",
    description: "People make me, save me, change me, raise me. What am I?",
    answers: ["money"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "Tomorrow",
    description: "What is always coming but never arrives?",
    answers: ["tomorrow"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Painting",
    description:
      "A man looks at a painting in a museum and says, \"Brothers and sisters I have none, but that man's father is my father's son.\" Who is in the painting?",
    answers: ["the man's son", "man's son"],
    category: "logic",
    publish_status: "draft"
  },
  %{
    name: "The Shadow",
    description: "What's always found on the ground but never gets dirty?",
    answers: ["a shadow", "shadow"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Keyboard 2",
    description:
      "I have keys but no locks. I have space but no room. You can enter, but you can't go inside. What am I?",
    answers: ["keyboard"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Anchor",
    description:
      "What do you throw out when you want to use it but take in when you don't want to use it?",
    answers: ["an anchor", "anchor"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Needle",
    description: "What has one eye, but can't see?",
    answers: ["a needle", "needle"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Presidents",
    description:
      "The 22nd and 24th presidents of the United States of America had the same parents but were not brothers. How can this be possible?",
    answers: ["grover cleveland", "the same man", "same man"],
    category: "logic",
    publish_status: "draft"
  },
  %{
    name: "The Staircase",
    description: "What goes up and down but doesn't move?",
    answers: ["staircase"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Penny",
    description: "What has a head, a tail, is brown, and has no legs?",
    answers: ["a penny", "penny"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Boat",
    description:
      "You see a boat filled with people. It has not sunk, but when you look again you don't see a single person on the boat. Why?",
    answers: ["they were married", "married", "all the people were married"],
    category: "trick question",
    publish_status: "draft"
  },
  %{
    name: "Always Ahead",
    description: "What is always in front of you but can't be seen?",
    answers: ["the future", "future"],
    category: "what am i",
    publish_status: "draft"
  },
  %{
    name: "The Chalkboard",
    description: "What is black when it's clean and white when it's dirty?",
    answers: ["a chalkboard", "chalkboard"],
    category: "what am i",
    publish_status: "draft"
  }
]
