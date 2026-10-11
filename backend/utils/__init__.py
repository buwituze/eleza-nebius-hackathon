"""
backend/utils package — Utility functions for the pre-consultation system.
"""

from .session_logger import (
    log_session,
    log_unknown_symptom,
    get_session_statistics,
    get_unknown_symptoms_report,
    get_cost_analysis,
    generate_expansion_report,
    generate_performance_report
)

__all__ = [
    'log_session',
    'log_unknown_symptom',
    'get_session_statistics',
    'get_unknown_symptoms_report',
    'get_cost_analysis',
    'generate_expansion_report',
    'generate_performance_report'
]
