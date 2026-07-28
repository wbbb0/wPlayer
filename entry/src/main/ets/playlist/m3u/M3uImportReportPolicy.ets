export const MAX_M3U_REPORT_DETAILS_PER_SECTION: number = 500;

export class M3uImportReportPolicy {
  static displayCount(total: number): number {
    return Math.min(MAX_M3U_REPORT_DETAILS_PER_SECTION, Math.max(0, Math.round(total)));
  }

  static detailsTruncated(total: number): boolean {
    return total > MAX_M3U_REPORT_DETAILS_PER_SECTION;
  }
}

export class M3uImportReportBudget {
  private matched: number = 0;
  private unmatched: number = 0;
  private issues: number = 0;
  private failures: number = 0;

  retainMatched(requested: number): number {
    const retained = this.retainCount(this.matched, requested);
    this.matched += retained;
    return retained;
  }

  retainUnmatched(requested: number): number {
    const retained = this.retainCount(this.unmatched, requested);
    this.unmatched += retained;
    return retained;
  }

  retainIssues(requested: number): number {
    const retained = this.retainCount(this.issues, requested);
    this.issues += retained;
    return retained;
  }

  retainFailures(requested: number): number {
    const retained = this.retainCount(this.failures, requested);
    this.failures += retained;
    return retained;
  }

  private retainCount(alreadyRetained: number, requested: number): number {
    const remaining = Math.max(0, MAX_M3U_REPORT_DETAILS_PER_SECTION - alreadyRetained);
    return Math.min(remaining, Math.max(0, Math.round(requested)));
  }
}
