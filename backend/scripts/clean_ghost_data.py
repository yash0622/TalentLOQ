from pymongo import MongoClient

client = MongoClient('mongodb://localhost:27017')
db = client['talentloq_db']

for s in db.students.find():
    print('Student in DB:', s.get('full_name'), '| has_resume:', s.get('has_resume'), '| filename:', s.get('resume_filename'), '| url:', s.get('resume_url'))

# Clean fake resume.pdf or placeholder
res = db.students.update_many(
    {'$or': [
        {'resume_filename': 'resume.pdf'},
        {'resume_url': '/static/uploads/resume.pdf'},
        {'resume_filename': {'$regex': 'jane_smith', '$options': 'i'}},
    ]},
    {'$set': {
        'has_resume': False,
        'resume_filename': None,
        'resume_url': None,
        'resume_id': None,
        'resume_uploaded_at': None,
        'resume_confidence': None,
    }}
)
print('Updated fake placeholder resumes:', res.modified_count)
