const onlyDigits = (value: string): string => value.replace(/\D+/g, "");

export function normalizePhone(input: string | null | undefined): string | null {
  if (!input) {
    return null;
  }

  const digits = onlyDigits(input);
  if (digits.length < 10) {
    return null;
  }

  if (digits.startsWith("55")) {
    return digits;
  }

  return `55${digits}`;
}

export function normalizeEmail(input: string | null | undefined): string | null {
  if (!input) {
    return null;
  }

  const email = input.trim().toLowerCase();
  return email.includes("@") ? email : null;
}
