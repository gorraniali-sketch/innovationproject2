export type AuthActionState = {
  status: "idle" | "success" | "error";
  message: string;
};

export type AuthAction = (
  previousState: AuthActionState,
  formData: FormData,
) => Promise<AuthActionState>;

export const initialAuthActionState: AuthActionState = {
  status: "idle",
  message: "",
};

export const minimumPasswordLength = 8;
export const maximumPasswordLength = 128;

export function normalizeEmail(value: string): string {
  return value.trim().toLowerCase();
}

export function isValidEmail(value: string): boolean {
  return (
    value.length <= 254 &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)
  );
}

export function isValidPassword(value: string): boolean {
  return (
    value.length >= minimumPasswordLength &&
    value.length <= maximumPasswordLength
  );
}

export type AuthRedirectPath =
  | "/auth/confirmed"
  | "/auth/update-password";

export function getAuthRedirectPath(value: string | null): AuthRedirectPath {
  if (value === "/auth/update-password") {
    return value;
  }

  return "/auth/confirmed";
}
