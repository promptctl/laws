# roster

Command-line roster for the tutoring programme.

```sh
python3 roster.py list               # every learner
python3 roster.py course <course-id> # learners enrolled in one course
```

Data lives in `learners.json`. Each learner has an id, a name, an email, the courses
they are enrolled in, and the date they last logged in to the portal.

## Glossary

- **Learner**: anyone enrolled in at least one course.
- **Tutor**: the person who runs a course.
- **Course**: one subject taught over a term; identified by a short code like `ALG1`.
