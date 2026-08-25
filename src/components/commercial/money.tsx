import { roundMoney } from "@/server/domain/commercial";

export function MoneyDisplay({
  amount,
  currency = "SAR",
}: {
  amount: number | string | null | undefined;
  currency?: string;
}) {
  const n = amount == null ? 0 : Number(amount);
  return (
    <span className="tabular-nums">
      {roundMoney(n).toLocaleString("ar-SA", { minimumFractionDigits: 2 })} {currency}
    </span>
  );
}
