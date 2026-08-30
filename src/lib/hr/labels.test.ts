import { describe, expect, it } from "vitest";
import {
  CONTRACT_STATUS_LABELS,
  DOCUMENT_CATEGORY_LABELS,
  EMPLOYEE_DIRECTORY_COLUMNS,
  VISIBILITY_SCOPE_LABELS,
  contractStatusLabel,
  documentCategoryLabel,
  employmentTypeLabel,
  genderLabel,
  maskIban,
  visibilityScopeLabel,
} from "./labels";

describe("hr labels", () => {
  it("maps employment types centrally", () => {
    expect(employmentTypeLabel("permanent")).toMatch(/دائم|Permanent/);
    expect(employmentTypeLabel("consultant")).toMatch(/استشار|Consultant/);
  });

  it("maps gender labels", () => {
    expect(genderLabel("male")).toBeTruthy();
    expect(genderLabel(null)).toBe("—");
  });

  it("maps contract status and document categories", () => {
    expect(contractStatusLabel("active")).toBe(CONTRACT_STATUS_LABELS.active.ar);
    expect(documentCategoryLabel("passport")).toBe(DOCUMENT_CATEGORY_LABELS.passport.ar);
    expect(visibilityScopeLabel("hr_only")).toBe(VISIBILITY_SCOPE_LABELS.hr_only.ar);
  });

  it("masks IBAN properly while preserving 4-char prefix and suffix", () => {
    expect(maskIban("SA0380000000608010167519")).toBe("SA03 **** **** **** 7519");
    expect(maskIban("SA 03 8000 0000 6080 1016 7519")).toBe("SA03 **** **** **** 7519");
    expect(maskIban(null)).toBe("—");
    expect(maskIban("123")).toBe("****");
  });

  it("directory columns never include compensation or ID docs", () => {
    const cols = EMPLOYEE_DIRECTORY_COLUMNS;
    expect(cols).not.toMatch(/salary|allowance|compensation|bank|iqama|passport|gosi/i);
    expect(cols).not.toMatch(/date_of_birth|gender/);
    expect(cols).toContain("employee_number");
    expect(cols).toContain("employment_type");
  });
});
