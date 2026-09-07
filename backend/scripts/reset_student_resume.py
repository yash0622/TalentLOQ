from pymongo import MongoClient

client = MongoClient('mongodb://localhost:27017')
db = client['talentloq_db']

res = db.students.update_many(
    {},
    {'$set': {
        'has_resume': False,
        'resume_filename': None,
        'resume_url': None,
        'resume_id': None,
        'resume_uploaded_at': None,
        'resume_confidence': None,
    }}
)
print('Reset student resumes to False/None count:', res.modified_count)

for s in db.students.find():
    print('Student in DB now:', s.get('full_name'), '| has_resume:', s.get('has_resume'), '| filename:', s.get('resume_filename'))
