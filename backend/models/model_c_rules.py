"""
models/model_c_rules.py — Rule-based question trees for common symptoms.

NEW SYSTEM (March 2026):
Symptom-specific predefined questions to reduce API costs and improve consistency.

Initial symptoms covered:
1. Mouth problems (teeth, gums, tongue)
2. Stomachache
3. Headache
4. Backache

Expansion: Add more symptoms based on usage data.
"""

import json
import os
from typing import List, Dict, Optional
from datetime import datetime

# ============================================================================
# PATIENT INFO QUESTIONS (Always ask FIRST)
# ============================================================================

PATIENT_INFO_QUESTIONS = {
    "kinyarwanda": [
        {
            "id": "patient_name",
            "question": "Izina ryanyu ni irihe?",
            "targets": "patient_name",
            "priority": 1,
            "required": True
        },
        {
            "id": "patient_age",
            "question": "Mufite imyaka ingahe?",
            "targets": "patient_age",
            "priority": 2,
            "required": True
        },
        {
            "id": "patient_gender",
            "question": "Uri umugabo cg umutegarugori?",
            "targets": "patient_gender",
            "priority": 3,
            "required": True
        },
        {
            "id": "patient_phone",
            "question": "Nimero ya telefone yanyu ni iyihe?",
            "targets": "patient_phone",
            "priority": 4,
            "required": True
        },
        {
            "id": "patient_location",
            "question": "Mutuye hehe cyangwa muri aka gace akahe?",
            "targets": "patient_location",
            "priority": 5,
            "required": True
        }
    ],
    "english": [
        {
            "id": "patient_name",
            "question": "What is your name?",
            "targets": "patient_name",
            "priority": 1,
            "required": True
        },
        {
            "id": "patient_age",
            "question": "How old are you?",
            "targets": "patient_age",
            "priority": 2,
            "required": True
        },
        {
            "id": "patient_gender",
            "question": "What is your gender? Male or female?",
            "targets": "patient_gender",
            "priority": 3,
            "required": True
        },
        {
            "id": "patient_phone",
            "question": "What is your phone number?",
            "targets": "patient_phone",
            "priority": 4,
            "required": True
        },
        {
            "id": "patient_location",
            "question": "Where do you live?",
            "targets": "patient_location",
            "priority": 5,
            "required": True
        }
    ]
}

# ============================================================================
# SYMPTOM QUESTION TREES
# ============================================================================

SYMPTOM_QUESTION_TREES = {
    # ========================================================================
    # 1. MOUTH PROBLEMS (teeth, gums, tongue)
    # ========================================================================
    "mouth_problems": {
        "priority": 1,
        "kinyarwanda": [
            {
                "id": "mouth_location",
                "question": "Ikibazo kiri hehe mu kanwa? Ku menyo, ku rurimi, cyangwa ku rusi?",
                "targets": "body_part",
                "priority": 1
            },
            {
                "id": "mouth_symptoms",
                "question": "Wabonye ububabare, kubyimba, cyangwa amaraso?",
                "targets": "associated_symptoms",
                "priority": 2
            },
            {
                "id": "mouth_onset",
                "question": "Ibi byatangiye ryari? Byatangiye ako kanya cyangwa byagenda bitanguye?",
                "targets": "duration",
                "priority": 3
            }
        ],
        "english": [
            {
                "id": "mouth_location",
                "question": "Where is the problem in your mouth? Teeth, tongue, or gums?",
                "targets": "body_part",
                "priority": 1
            },
            {
                "id": "mouth_symptoms",
                "question": "Do you have pain, swelling, or bleeding?",
                "targets": "associated_symptoms",
                "priority": 2
            },
            {
                "id": "mouth_onset",
                "question": "When did this start? Sudden or gradual?",
                "targets": "duration",
                "priority": 3
            }
        ],
        "red_flag_checks": [
            "severe_swelling_blocking_breathing",
            "cannot_swallow",
            "facial_swelling_spreading_rapidly"
        ]
    },
    
    # ========================================================================
    # 2. STOMACHACHE
    # ========================================================================
    "stomach_pain": {
        "priority": 2,
        "kinyarwanda": [
            {
                "id": "stomach_location",
                "question": "Ububabare bw'inda buri hehe? Hejuru, hasi, cyangwa ahantu hose?",
                "targets": "body_part",
                "priority": 1
            },
            {
                "id": "stomach_symptoms",
                "question": "Urafite impiswi, kuruka, cyangwa kugira nabi?",
                "targets": "associated_symptoms",
                "priority": 2
            },
            {
                "id": "stomach_triggers",
                "question": "Wariye ikintu kidasanzwe mu masaha 24 ashize?",
                "targets": "triggers",
                "priority": 3
            }
        ],
        "english": [
            {
                "id": "stomach_location",
                "question": "Where is the stomach pain? Upper, lower, or all over?",
                "targets": "body_part",
                "priority": 1
            },
            {
                "id": "stomach_symptoms",
                "question": "Do you have diarrhea, vomiting, or nausea?",
                "targets": "associated_symptoms",
                "priority": 2
            },
            {
                "id": "stomach_triggers",
                "question": "Did you eat anything unusual in the last 24 hours?",
                "targets": "triggers",
                "priority": 3
            }
        ],
        "red_flag_checks": [
            "severe_lower_right_pain",  # Appendicitis
            "rigid_abdomen",
            "vomiting_blood",
            "black_tarry_stools"
        ]
    },
    
    # ========================================================================
    # 3. HEADACHE
    # ========================================================================
    "headache": {
        "priority": 3,
        "kinyarwanda": [
            {
                "id": "headache_location",
                "question": "Ububabare bw'umutwe buri kuruhande rumwe cyangwa ku ruhande rwombi?",
                "targets": "body_part",
                "priority": 1
            },
            {
                "id": "headache_symptoms",
                "question": "Urafite isesemi, kuruka, cyangwa imitsi ikurwana?",
                "targets": "associated_symptoms",
                "priority": 2
            },
            {
                "id": "headache_quality",
                "question": "Ibi byatangiye ryari? Bimeze bite - biratera, birakaza, cyangwa bihoraho?",
                "targets": "duration,quality",
                "priority": 3
            }
        ],
        "english": [
            {
                "id": "headache_location",
                "question": "Is the headache on one side or both sides of your head?",
                "targets": "body_part",
                "priority": 1
            },
            {
                "id": "headache_symptoms",
                "question": "Do you have nausea, vomiting, or sensitivity to light?",
                "targets": "associated_symptoms",
                "priority": 2
            },
            {
                "id": "headache_quality",
                "question": "When did this start? What's it like - throbbing, sharp, or constant?",
                "targets": "duration,quality",
                "priority": 3
            }
        ],
        "red_flag_checks": [
            "worst_headache_ever",
            "sudden_thunderclap_onset",
            "with_fever_and_stiff_neck",  # Meningitis
            "after_head_injury",
            "with_confusion_or_weakness"
        ]
    },
    
    # ========================================================================
    # 4. BACKACHE
    # ========================================================================
    "backache": {
        "priority": 4,
        "kinyarwanda": [
            {
                "id": "back_location",
                "question": "Ububabare buri hehe ku mugongo? Hejuru, hagati, cyangwa hasi?",
                "targets": "body_part",
                "priority": 1
            },
            {
                "id": "back_mobility",
                "question": "Ububabare butuma udashobora kugenda cyangwa kwinama?",
                "targets": "associated_symptoms",
                "priority": 2
            },
            {
                "id": "back_triggers",
                "question": "Waguye, wakoze akazi gakomeye, cyangwa wacayeho iminsi?",
                "targets": "triggers,duration",
                "priority": 3
            }
        ],
        "english": [
            {
                "id": "back_location",
                "question": "Where is the back pain? Upper back, middle, or lower back?",
                "targets": "body_part",
                "priority": 1
            },
            {
                "id": "back_mobility",
                "question": "Does the pain make it hard to walk or bend?",
                "targets": "associated_symptoms",
                "priority": 2
            },
            {
                "id": "back_triggers",
                "question": "Did you fall, do heavy work, or has this been ongoing for days?",
                "targets": "triggers,duration",
                "priority": 3
            }
        ],
        "red_flag_checks": [
            "cannot_move_legs",
            "loss_of_bladder_control",
            "numbness_in_groin_area",  # Cauda equina syndrome
            "severe_trauma",
            "fever_with_back_pain"
        ]
    },
    
    # ========================================================================
    # DEFAULT FALLBACK (Unknown symptoms → use AI)
    # ========================================================================
    "_default": {
        "priority": 999,
        "kinyarwanda": [
            {
                "id": "default_onset",
                "question": "Ibi byatangiye ryari?",
                "targets": "duration",
                "priority": 1
            },
            {
                "id": "default_severity",
                "question": "Kuri ishamihere rya 1-10, birakomeye bingahe?",
                "targets": "severity",
                "priority": 2
            },
            {
                "id": "default_symptoms",
                "question": "Hari ibindi bimenyetso ufite?",
                "targets": "associated_symptoms",
                "priority": 3
            }
        ],
        "english": [
            {
                "id": "default_onset",
                "question": "When did this start?",
                "targets": "duration",
                "priority": 1
            },
            {
                "id": "default_severity",
                "question": "On a scale of 1-10, how severe is it?",
                "targets": "severity",
                "priority": 2
            },
            {
                "id": "default_symptoms",
                "question": "Do you have any other symptoms?",
                "targets": "associated_symptoms",
                "priority": 3
            }
        ],
        "fallback_to_ai": True  # Always use AI for unknown symptoms
    }
}

# ============================================================================
# COMPLAINT NORMALIZATION MAPPINGS
# ============================================================================

COMPLAINT_MAPPINGS = {
    "mouth_problems": [
        "mouth", "tooth", "teeth", "gum", "gums", "tongue", "dental",
        "menyo", "amenyo", "ijisho", "rusi", "rurimi", "kanwa",
        "toothache", "tooth pain", "gum pain"
    ],
    "stomach_pain": [
        "stomach", "belly", "abdomen", "abdominal", "tummy",
        "inda", "nda", "stomach pain", "belly ache", "ububabare bw'inda"
    ],
    "headache": [
        "head", "headache", "migraine", "head pain",
        "umutwe", "mutwe", "ububabare bw'umutwe", "umutwe ubuza"
    ],
    "backache": [
        "back", "backache", "back pain", "spine",
        "umugongo", "mugongo", "ububabare bw'umugongo"
    ]
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def normalize_complaint(complaint: str) -> str:
    """
    Normalize complaint variations to canonical symptom name.
    
    Args:
        complaint: Patient's chief complaint (from light extraction)
    
    Returns:
        Canonical symptom name or "unknown"
    
    Examples:
        "umutwe" → "headache"
        "stomach ache" → "stomach_pain"
        "amenyo" → "mouth_problems"
    """
    complaint_lower = complaint.lower().strip()
    
    for canonical, variations in COMPLAINT_MAPPINGS.items():
        if any(var in complaint_lower for var in variations):
            return canonical
    
    return "unknown"


def get_patient_info_questions(language: str = "kinyarwanda") -> List[Dict]:
    """
    Get patient information questions (name, age, gender).
    These should ALWAYS be asked first.
    
    Returns:
        List of question dicts with id, question, targets, priority
    """
    return PATIENT_INFO_QUESTIONS.get(language, PATIENT_INFO_QUESTIONS["kinyarwanda"])


def get_symptom_questions(chief_complaint: str, language: str = "kinyarwanda") -> Optional[List[Dict]]:
    """
    Get symptom-specific questions for a given complaint.
    
    Args:
        chief_complaint: Normalized complaint name (from light extraction)
        language: "kinyarwanda" or "english"
    
    Returns:
        List of question dicts, or None if symptom not in trees (use AI)
    
    Examples:
        get_symptom_questions("headache", "kinyarwanda")
        → Returns 3 headache-specific questions in Kinyarwanda
        
        get_symptom_questions("rare_disease", "english")
        → Returns None (unknown symptom, use AI conversation)
    """
    # Normalize the complaint first
    normalized = normalize_complaint(chief_complaint)
    
    # Check if we have a question tree for this symptom
    if normalized not in SYMPTOM_QUESTION_TREES:
        log_unknown_symptom(chief_complaint)
        return None  # Signal to use AI conversation
    
    tree = SYMPTOM_QUESTION_TREES[normalized]
    
    # Check if this symptom should fallback to AI
    if tree.get("fallback_to_ai", False):
        return None
    
    # Return questions in requested language
    questions = tree.get(language, tree.get("kinyarwanda", []))
    return questions


def get_red_flag_checks(chief_complaint: str) -> List[str]:
    """
    Get symptom-specific red flag indicators.
    
    Args:
        chief_complaint: Normalized complaint name
    
    Returns:
        List of red flag identifiers for this symptom
    """
    normalized = normalize_complaint(chief_complaint)
    
    if normalized in SYMPTOM_QUESTION_TREES:
        return SYMPTOM_QUESTION_TREES[normalized].get("red_flag_checks", [])
    
    return []


def has_question_tree(chief_complaint: str) -> bool:
    """
    Check if we have a question tree for this symptom.
    
    Args:
        chief_complaint: Complaint string
    
    Returns:
        True if we have predefined questions, False otherwise
    """
    normalized = normalize_complaint(chief_complaint)
    return normalized in SYMPTOM_QUESTION_TREES and not SYMPTOM_QUESTION_TREES[normalized].get("fallback_to_ai", False)


def get_all_covered_symptoms() -> List[str]:
    """
    Get list of all symptoms with question trees.
    
    Returns:
        List of canonical symptom names we can handle with rules
    """
    return [
        symptom for symptom in SYMPTOM_QUESTION_TREES.keys()
        if symptom != "_default" and not SYMPTOM_QUESTION_TREES[symptom].get("fallback_to_ai", False)
    ]


# ============================================================================
# LOGGING FOR EXPANSION
# ============================================================================

_UNKNOWN_SYMPTOMS_LOG = []

def log_unknown_symptom(complaint: str):
    """
    Log unknown symptoms for future expansion planning.
    
    This helps track which symptoms are commonly seen but not yet
    covered by rule-based questions.
    """
    _UNKNOWN_SYMPTOMS_LOG.append({
        "complaint": complaint,
        "timestamp": datetime.now().isoformat()
    })
    
    # In production, this would write to database
    # For now, just track in memory
    print(f"[EXPANSION] Unknown symptom logged: {complaint}")


def get_unknown_symptoms_report() -> Dict:
    """
    Get summary of unknown symptoms for expansion planning.
    
    Returns:
        Dict with symptom counts and suggestions
    """
    from collections import Counter
    
    complaints = [entry["complaint"] for entry in _UNKNOWN_SYMPTOMS_LOG]
    counts = Counter(complaints)
    
    return {
        "total_unknown": len(_UNKNOWN_SYMPTOMS_LOG),
        "unique_symptoms": len(counts),
        "top_10": counts.most_common(10),
        "expansion_candidates": [symptom for symptom, count in counts.most_common(5) if count >= 3]
    }


# ============================================================================
# CONFIGURATION
# ============================================================================

def get_coverage_stats() -> Dict:
    """
    Get statistics about rule-based coverage.
    
    Returns:
        Dict with coverage information
    """
    return {
        "symptoms_covered": len(get_all_covered_symptoms()),
        "languages_supported": ["kinyarwanda", "english"],
        "patient_info_questions": len(PATIENT_INFO_QUESTIONS["kinyarwanda"]),
        "avg_questions_per_symptom": 3,
        "symptom_list": get_all_covered_symptoms()
    }


if __name__ == "__main__":
    # Test the module
    print("=" * 70)
    print("MODEL C RULES - Rule-Based Question Trees")
    print("=" * 70)
    
    stats = get_coverage_stats()
    print(f"\n📊 Coverage Statistics:")
    print(f"   Symptoms covered: {stats['symptoms_covered']}")
    print(f"   Languages: {', '.join(stats['languages_supported'])}")
    print(f"   Symptoms: {', '.join(stats['symptom_list'])}")
    
    print(f"\n❓ Patient Info Questions (Kinyarwanda):")
    for q in get_patient_info_questions("kinyarwanda"):
        print(f"   {q['priority']}. {q['question']}")
    
    print(f"\n🏥 Headache Questions (English):")
    questions = get_symptom_questions("headache", "english")
    if questions:
        for q in questions:
            print(f"   {q['priority']}. {q['question']}")
    
    print(f"\n🔍 Testing complaint normalization:")
    test_complaints = ["umutwe ubuza", "stomach ache", "amenyo", "unknown illness"]
    for complaint in test_complaints:
        normalized = normalize_complaint(complaint)
        has_tree = has_question_tree(complaint)
        print(f"   '{complaint}' → '{normalized}' (has tree: {has_tree})")
