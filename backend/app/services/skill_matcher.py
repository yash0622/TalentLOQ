"""
Skill Matching & Extraction Service for TalentLOQ.
Uses spaCy's PhraseMatcher against a curated, bounded skills taxonomy.
Zero external ML training, deterministic, offline, and sub-millisecond execution.
"""
from typing import List, Set, Dict, Optional, Any
import spacy
from spacy.matcher import PhraseMatcher

# Load lightweight spaCy core model once at module import
nlp = spacy.load("en_core_web_sm")

# Curated, normalized taxonomy mapping aliases and common variations to canonical skill names.
SKILLS_TAXONOMY: Dict[str, str] = {
    # Programming Languages
    "python": "Python",
    "python3": "Python",
    "java": "Java",
    "c++": "C++",
    "cpp": "C++",
    "c#": "C#",
    "c language": "C",
    "c programming": "C",
    "javascript": "JavaScript",
    "js": "JavaScript",
    "typescript": "TypeScript",
    "ts": "TypeScript",
    "dart": "Dart",
    "golang": "Go",
    "go": "Go",
    "ruby": "Ruby",
    "php": "PHP",
    "rust": "Rust",
    "kotlin": "Kotlin",
    "r programming": "R",
    "r language": "R",
    "r script": "R",
    "scala": "Scala",

    # Web & Mobile Frameworks
    "flutter": "Flutter",
    "react": "React",
    "react.js": "React",
    "reactjs": "React",
    "react native": "React Native",
    "angular": "Angular",
    "angularjs": "Angular",
    "vue": "Vue.js",
    "vue.js": "Vue.js",
    "vuejs": "Vue.js",
    "node": "Node.js",
    "node.js": "Node.js",
    "nodejs": "Node.js",
    "express": "Express.js",
    "express.js": "Express.js",
    "fastapi": "FastAPI",
    "django": "Django",
    "flask": "Flask",
    "spring": "Spring Boot",
    "spring boot": "Spring Boot",
    "html": "HTML5",
    "html5": "HTML5",
    "css": "CSS3",
    "css3": "CSS3",
    "tailwind": "Tailwind CSS",
    "tailwindcss": "Tailwind CSS",
    "bootstrap": "Bootstrap",

    # Databases & Caching
    "sql": "SQL",
    "postgresql": "PostgreSQL",
    "postgres": "PostgreSQL",
    "mysql": "MySQL",
    "sqlite": "SQLite",
    "mongodb": "MongoDB",
    "redis": "Redis",
    "cassandra": "Cassandra",
    "oracle": "Oracle DB",
    "firebase": "Firebase",
    "firestore": "Cloud Firestore",

    # Cloud, DevOps & Infrastructure
    "docker": "Docker",
    "kubernetes": "Kubernetes",
    "k8s": "Kubernetes",
    "aws": "AWS",
    "amazon web services": "AWS",
    "azure": "Azure",
    "gcp": "GCP",
    "google cloud": "GCP",
    "google cloud platform": "GCP",
    "git": "Git",
    "github": "GitHub",
    "gitlab": "GitLab",
    "ci/cd": "CI/CD",
    "jenkins": "Jenkins",
    "linux": "Linux",
    "rest api": "REST APIs",
    "rest apis": "REST APIs",
    "restful": "REST APIs",
    "graphql": "GraphQL",
    "websockets": "WebSockets",
    "websocket": "WebSockets",

    # AI, Machine Learning & Data Science
    "machine learning": "Machine Learning",
    "ml": "Machine Learning",
    "deep learning": "Deep Learning",
    "artificial intelligence": "AI/ML",
    "ai": "AI/ML",
    "ai/ml": "AI/ML",
    "data science": "Data Science",
    "nlp": "NLP",
    "natural language processing": "NLP",
    "computer vision": "Computer Vision",
    "cv": "Computer Vision",
    "pandas": "Pandas",
    "numpy": "NumPy",
    "scikit-learn": "Scikit-Learn",
    "sklearn": "Scikit-Learn",
    "pytorch": "PyTorch",
    "tensorflow": "TensorFlow",
    "keras": "Keras",
    "rag": "RAG",
    "llm": "LLMs",
    "llms": "LLMs",
    "large language models": "LLMs",
    "data analysis": "Data Analysis",
    "tableau": "Tableau",
    "power bi": "Power BI",

    # Core Engineering & Soft Skills
    "communication": "Communication Skills",
    "communication skills": "Communication Skills",
    "verbal communication": "Communication Skills",
    "written communication": "Communication Skills",
    "analytical skills": "Analytical Skills",
    "problem solving": "Problem Solving",
    "critical thinking": "Critical Thinking",
    "teamwork": "Teamwork",
    "leadership": "Leadership",
    "agile": "Agile Methodologies",
    "scrum": "Scrum",
    "dsa": "Data Structures & Algorithms",
    "data structures": "Data Structures & Algorithms",
    "algorithms": "Data Structures & Algorithms",
    "object oriented programming": "OOP",
    "oop": "OOP",
}

CANONICAL_SKILL_EQUIVALENCE: Dict[str, List[str]] = {
    "FastAPI": ["REST APIs", "Python", "Backend"],
    "Django": ["REST APIs", "Python", "Backend"],
    "Flask": ["REST APIs", "Python", "Backend"],
    "Express.js": ["REST APIs", "JavaScript", "Node.js", "Backend"],
    "Flutter": ["Mobile Development", "Dart", "Cross-Platform"],
    "React Native": ["Mobile Development", "JavaScript", "TypeScript", "React"],
    "Docker": ["Containers", "DevOps", "CI/CD"],
    "Kubernetes": ["Containers", "DevOps", "Cloud"],
    "AWS": ["Cloud", "DevOps", "Infrastructure"],
    "GCP": ["Cloud", "DevOps", "Infrastructure"],
    "Azure": ["Cloud", "DevOps", "Infrastructure"],
    "PostgreSQL": ["SQL", "Databases", "RDBMS"],
    "MySQL": ["SQL", "Databases", "RDBMS"],
    "MongoDB": ["NoSQL", "Databases"],
    "PyTorch": ["Machine Learning", "Deep Learning", "AI/ML"],
    "TensorFlow": ["Machine Learning", "Deep Learning", "AI/ML"],
    "Scikit-Learn": ["Machine Learning", "Data Science"],
    "Pandas": ["Data Analysis", "Python", "Data Science"],
    "NumPy": ["Data Analysis", "Python", "Data Science"],
}

class SkillMatcherEngine:
    """PhraseMatcher engine for high-speed bounded skill extraction."""
    def __init__(self, taxonomy: Dict[str, str] = SKILLS_TAXONOMY):
        self.taxonomy = taxonomy
        self.matcher = PhraseMatcher(nlp.vocab, attr="LOWER")
        # Build patterns from taxonomy keys
        patterns = [nlp.make_doc(alias) for alias in self.taxonomy.keys()]
        self.matcher.add("SKILLS_TAXONOMY", patterns)

    def extract_skills_from_text(self, text: Optional[str]) -> List[str]:
        """
        Extracts and normalizes skills from unstructured text (drive description or resume)
        into their canonical representations.
        """
        if not text or not text.strip():
            return []

        # Fast sub-millisecond tokenization without heavy neural pipelines (tagger, parser, ner)
        doc = nlp.make_doc(text)
        matches = self.matcher(doc)

        found_canonical: Set[str] = set()
        for match_id, start, end in matches:
            matched_text = doc[start:end].text.lower().strip()
            if matched_text in self.taxonomy:
                found_canonical.add(self.taxonomy[matched_text])

        return sorted(list(found_canonical))

    def get_equivalent_skills(self, skill: str) -> List[str]:
        canon = self.taxonomy.get(skill.lower().strip(), skill.strip())
        return CANONICAL_SKILL_EQUIVALENCE.get(canon, [])

    def compute_skill_overlap(
        self,
        candidate_skills: List[str],
        required_skills: List[str]
    ) -> Dict[str, Any]:
        """
        Computes deterministic exact & semantic skill overlap between a student's skills and a job drive.
        """
        cand_normalized = {self.taxonomy.get(s.lower(), s.strip()) for s in candidate_skills if s and s.strip()}
        req_normalized = {self.taxonomy.get(r.lower(), r.strip()) for r in required_skills if r and r.strip()}

        exact_matched = set(cand_normalized & req_normalized)
        missing = set(req_normalized - cand_normalized)

        semantic_equivalences = []
        for c in cand_normalized:
            equivs = CANONICAL_SKILL_EQUIVALENCE.get(c, [])
            for r in list(missing):
                if r in equivs or any(e.lower() == r.lower() for e in equivs):
                    semantic_equivalences.append({
                        "student_skill": c,
                        "job_requirement": r,
                        "transferability": "High",
                        "reasoning": f"{c} directly demonstrates competence in {r}."
                    })
                    exact_matched.add(r)
                    missing.discard(r)

        matched = sorted(list(exact_matched))
        unmet = sorted(list(missing))
        total_req = max(len(req_normalized), 1)
        overlap_ratio = len(matched) / total_req

        return {
            "matched_skills": matched,
            "missing_skills": unmet,
            "match_count": len(matched),
            "total_required": len(req_normalized),
            "overlap_ratio": overlap_ratio,
            "semantic_equivalences": semantic_equivalences,
            "is_exact_match": len(unmet) == 0 and len(req_normalized) > 0,
        }

# Global singleton instance for app-wide use
skill_matcher_engine = SkillMatcherEngine()
