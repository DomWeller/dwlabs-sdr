const phonePattern = /\b55\d{10,13}\b/g;
const emailPattern = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi;

export function redactSensitiveText(input: string): string {
  return input
    .replace(phonePattern, "[telefone-redigido]")
    .replace(emailPattern, "[email-redigido]");
}
