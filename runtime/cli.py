"""
Matrix CLI — command-line interface for Matrix operations.

Commands:
  matrix tasks list     — Show all active tasks
  matrix tasks show ID  — Show task details
  matrix tasks cancel ID — Cancel a task
  matrix doctor         — Run full system health check
  matrix skills list    — List available skills
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import List


def main(argv: List[str] = None) -> int:
    parser = argparse.ArgumentParser(prog="matrix", description="Matrix Runtime CLI")
    sub = parser.add_subparsers(dest="command")

    # tasks
    tasks_p = sub.add_parser("tasks", help="Background task control plane")
    tasks_sub = tasks_p.add_subparsers(dest="tasks_action")

    list_p = tasks_sub.add_parser("list", help="List active tasks")
    list_p.add_argument("--agent", default="", help="Filter by agent (neo/trinity/morpheus)")
    list_p.add_argument("--status", default="", help="Filter by status")
    list_p.add_argument("--all", action="store_true", help="Show all tasks, not just active")

    show_p = tasks_sub.add_parser("show", help="Show task details")
    show_p.add_argument("task_id", help="Task ID to show")

    cancel_p = tasks_sub.add_parser("cancel", help="Cancel a running task")
    cancel_p.add_argument("task_id", help="Task ID to cancel")

    summary_p = tasks_sub.add_parser("summary", help="Plain-language summary of what's happening")

    # flows
    flows_p = sub.add_parser("flows", help="Task flow management")
    flows_sub = flows_p.add_subparsers(dest="flows_action")
    flows_sub.add_parser("list", help="List flows")
    flow_show_p = flows_sub.add_parser("show", help="Show flow details")
    flow_show_p.add_argument("flow_id", help="Flow ID")
    flow_cancel_p = flows_sub.add_parser("cancel", help="Cancel a flow")
    flow_cancel_p.add_argument("flow_id", help="Flow ID")

    # doctor
    sub.add_parser("doctor", help="Run system health diagnostics")

    # skills
    skills_p = sub.add_parser("skills", help="Skills marketplace")
    skills_sub = skills_p.add_subparsers(dest="skills_action")
    skills_sub.add_parser("list", help="List available skills")
    skills_sub.add_parser("reload", help="Reload skills from disk")

    args = parser.parse_args(argv)

    if args.command == "tasks":
        return _handle_tasks(args)
    elif args.command == "flows":
        return _handle_flows(args)
    elif args.command == "doctor":
        return _handle_doctor()
    elif args.command == "skills":
        return _handle_skills(args)
    else:
        parser.print_help()
        return 0


def _handle_tasks(args) -> int:
    from runtime.tasks import TaskLedger, TaskStatus
    ledger = TaskLedger()

    if args.tasks_action == "list":
        if args.all:
            tasks = ledger.list_tasks(agent=args.agent, limit=50)
        elif args.status:
            tasks = ledger.list_tasks(agent=args.agent, status=TaskStatus(args.status))
        else:
            tasks = ledger.list_active_tasks()

        if not tasks:
            print("No tasks found.")
            return 0

        print(f"{'ID':<16} {'Agent':<10} {'Status':<12} {'Title'}")
        print("-" * 70)
        for t in tasks:
            print(f"{t.task_id:<16} {t.agent:<10} {t.status.value:<12} {t.title[:40]}")
        return 0

    elif args.tasks_action == "show":
        task = ledger.get_task(args.task_id)
        if task is None:
            print(f"Task {args.task_id} not found.")
            return 1
        print(f"\n  Task:     {task.task_id}")
        print(f"  Title:    {task.title}")
        print(f"  Agent:    {task.agent}")
        print(f"  Status:   {task.status.value}")
        print(f"  Progress: {task.progress_pct}%")
        print(f"\n  What's happening:")
        print(f"  {task.plain_status}")
        if task.error:
            print(f"\n  Error: {task.error}")
        if task.result:
            print(f"\n  Result: {task.result}")
        print()
        return 0

    elif args.tasks_action == "cancel":
        task = ledger.get_task(args.task_id)
        if task is None:
            print(f"Task {args.task_id} not found.")
            return 1
        try:
            task = ledger.cancel_task(args.task_id)
            print(f"Cancelled: {task.plain_status}")
            return 0
        except ValueError as e:
            print(str(e))
            return 1

    elif args.tasks_action == "summary":
        summary = ledger.get_summary()
        print(summary["summary"])
        return 0

    else:
        print("Usage: matrix tasks {list|show|cancel|summary}")
        return 0


def _handle_flows(args) -> int:
    from runtime.tasks import TaskLedger
    ledger = TaskLedger()

    if args.flows_action == "list":
        flows = ledger.list_flows()
        if not flows:
            print("No flows found.")
            return 0
        print(f"{'ID':<16} {'Agent':<10} {'Status':<12} {'Name'}")
        print("-" * 70)
        for f in flows:
            print(f"{f.flow_id:<16} {f.agent:<10} {f.status.value:<12} {f.name[:40]}")
        return 0

    elif args.flows_action == "show":
        flow = ledger.get_flow(args.flow_id)
        if flow is None:
            print(f"Flow {args.flow_id} not found.")
            return 1
        print(f"\n  Flow:   {flow.flow_id}")
        print(f"  Name:   {flow.name}")
        print(f"  Status: {flow.status.value}")
        print(f"  Step:   {flow.current_step + 1} of {len(flow.task_ids)}")
        print(f"\n  {flow.plain_status}")
        print()
        return 0

    elif args.flows_action == "cancel":
        flow = ledger.get_flow(args.flow_id)
        if flow is None:
            print(f"Flow {args.flow_id} not found.")
            return 1
        for tid in flow.task_ids:
            task = ledger.get_task(tid)
            if task and not task.is_terminal:
                ledger.cancel_task(tid)
        print(f"Flow {args.flow_id} cancelled.")
        return 0

    print("Usage: matrix flows {list|show|cancel}")
    return 0


def _handle_doctor() -> int:
    from runtime.doctor.diagnostics import run_doctor
    report = run_doctor()
    print(report["display"])
    return 0 if report["healthy"] else 1


def _handle_skills(args) -> int:
    from runtime.skills import SkillsRegistry
    registry = SkillsRegistry()

    if args.skills_action == "list":
        skills = registry.list_skills()
        if not skills:
            print("No skills installed.")
            return 0
        print(f"{'Name':<24} {'Version':<10} {'Agent':<12} {'Description'}")
        print("-" * 80)
        for s in skills:
            print(f"{s['name']:<24} {s.get('version', '-'):<10} {s.get('agent', 'all'):<12} {s.get('description', '')[:40]}")
        return 0

    elif args.skills_action == "reload":
        count = registry.reload()
        print(f"Reloaded {count} skills.")
        return 0

    print("Usage: matrix skills {list|reload}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
