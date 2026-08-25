import Link from "next/link";
import { Button } from "@/components/ui/primitives";

export function RegisterPagination({
  basePath,
  page,
  totalPages,
  params,
}: {
  basePath: string;
  page: number;
  totalPages: number;
  params: Record<string, string | undefined>;
}) {
  if (totalPages <= 1) return null;

  function href(p: number) {
    const q = new URLSearchParams();
    for (const [k, v] of Object.entries(params)) {
      if (v) q.set(k, v);
    }
    q.set("page", String(p));
    const qs = q.toString();
    return qs ? `${basePath}?${qs}` : basePath;
  }

  return (
    <div className="mt-4 flex items-center justify-between gap-3">
      <p className="text-sm text-muted">
        صفحة {page} من {totalPages}
      </p>
      <div className="flex gap-2">
        {page > 1 ? (
          <Link href={href(page - 1)}>
            <Button variant="secondary" type="button">
              السابق
            </Button>
          </Link>
        ) : null}
        {page < totalPages ? (
          <Link href={href(page + 1)}>
            <Button variant="secondary" type="button">
              التالي
            </Button>
          </Link>
        ) : null}
      </div>
    </div>
  );
}
