"use client";

import { ArrowDown, ArrowUp, ChevronsUpDown } from "lucide-react";

export function SortHeader({ label, field, sort, direction, onSort }: {
  label: string;
  field: string;
  sort: string;
  direction: "asc" | "desc";
  onSort: (field: string) => void;
}) {
  const Icon = sort !== field ? ChevronsUpDown : direction === "asc" ? ArrowUp : ArrowDown;
  return (
    <button className="group inline-flex items-center gap-1.5 font-semibold text-slate-600 hover:text-ink" onClick={() => onSort(field)}>
      {label}<Icon className="h-3.5 w-3.5 opacity-60" />
    </button>
  );
}
