"""
routing/ — Conversation routing logic and queue/department routing.
"""

from routing.conversation_router import (
    route_conversation,
    should_use_ai,
    get_conversation_strategy,
    format_routing_report,
    log_routing_decision,
    get_routing_statistics,
    ConversationMode
)

from routing.queue_routing import (
    assign_routing,
    suggest_unclear_issue_routing,
    get_queue_lengths,
    reset_queues,
    RoutingDecision
)

__all__ = [
    "route_conversation",
    "should_use_ai",
    "get_conversation_strategy",
    "format_routing_report",
    "log_routing_decision",
    "get_routing_statistics",
    "ConversationMode",
    "assign_routing",
    "suggest_unclear_issue_routing",
    "get_queue_lengths",
    "reset_queues",
    "RoutingDecision",
]
