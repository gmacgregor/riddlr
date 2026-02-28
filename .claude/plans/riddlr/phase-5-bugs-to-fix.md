1. add more fields to the new riddle form
   make sure the following fields are shown:

- :answers, {:array, :string}, default: []
- :play_status, :string, default: "closed"
- :live_date
- :publish_status

2. update solve time validation

- solve_time can be any number

3. make riddle categories a new schema

- :name, :string, default: "logic"
- a category belongs_to many riddles and a riddle has_one category
- seed categories: logic, trick question, wordplay/pun, "what am i"
- a riddle default category should be logic

4. categories can be edited & updated separately from riddles

5. when logged in as a admin, requests to /admin should redirect to /admin/riddles
