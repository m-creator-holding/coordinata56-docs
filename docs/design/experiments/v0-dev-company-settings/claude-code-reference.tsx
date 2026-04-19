/**
 * CompanySettingsPage — эталонный компонент, сгенерированный Claude Code.
 * Используется как reference для сравнения с выводом v0.dev.
 *
 * Стек: React 18 + TypeScript, Tailwind CSS v3.4, shadcn/ui, react-hook-form + zod.
 * Источник: wireframes-m-os-1-1-admin.md §«Экран 5. Company Settings»
 */

"use client";

import { useEffect, useState } from "react";
import { useForm, Controller } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { Link, useBlocker } from "react-router-dom";

import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Checkbox } from "@/components/ui/checkbox";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Alert, AlertDescription } from "@/components/ui/alert";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { useToast } from "@/components/ui/use-toast";
import { Separator } from "@/components/ui/separator";
import { Info } from "lucide-react";

// ---------------------------------------------------------------------------
// Схема валидации
// ---------------------------------------------------------------------------

const WEEKDAYS = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"] as const;
type Weekday = (typeof WEEKDAYS)[number];

const settingsSchema = z.object({
  vat_mode: z.enum(["none", "vat_20", "vat_10", "usn"], {
    required_error: "Выберите НДС-режим",
  }),
  currency: z.enum(["RUB", "USD", "EUR"], {
    required_error: "Выберите валюту",
  }),
  timezone: z.string({ required_error: "Выберите часовой пояс" }).min(1),
  workweek: z
    .array(z.enum(WEEKDAYS))
    .min(1, "Выберите хотя бы один рабочий день"),
  units: z.enum(["metric", "imperial"], {
    required_error: "Выберите единицы измерения",
  }),
  brand_color: z
    .string()
    .regex(/^#([0-9A-Fa-f]{6})$/, "Формат: #RRGGBB")
    .optional()
    .or(z.literal("")),
});

type SettingsFormValues = z.infer<typeof settingsSchema>;

// ---------------------------------------------------------------------------
// Константы
// ---------------------------------------------------------------------------

const VAT_OPTIONS = [
  { value: "none", label: "Без НДС" },
  { value: "vat_20", label: "НДС 20%" },
  { value: "vat_10", label: "НДС 10%" },
  { value: "usn", label: "УСН" },
] as const;

const CURRENCY_OPTIONS = [
  { value: "RUB", label: "RUB" },
  { value: "USD", label: "USD" },
  { value: "EUR", label: "EUR" },
] as const;

const TIMEZONE_OPTIONS = [
  { value: "Europe/Kaliningrad", label: "Europe/Kaliningrad (UTC+2)" },
  { value: "Europe/Moscow", label: "Europe/Moscow (UTC+3)" },
  { value: "Asia/Yekaterinburg", label: "Asia/Yekaterinburg (UTC+5)" },
  { value: "Asia/Novosibirsk", label: "Asia/Novosibirsk (UTC+7)" },
  { value: "Asia/Krasnoyarsk", label: "Asia/Krasnoyarsk (UTC+7)" },
  { value: "Asia/Irkutsk", label: "Asia/Irkutsk (UTC+8)" },
  { value: "Asia/Yakutsk", label: "Asia/Yakutsk (UTC+9)" },
  { value: "Asia/Vladivostok", label: "Asia/Vladivostok (UTC+10)" },
  { value: "Asia/Magadan", label: "Asia/Magadan (UTC+11)" },
  { value: "Asia/Kamchatka", label: "Asia/Kamchatka (UTC+12)" },
] as const;

const UNITS_OPTIONS = [
  { value: "metric", label: "Метрические (м, кг, м²)" },
  { value: "imperial", label: "Имперские" },
] as const;

const DEFAULT_WORKWEEK: Weekday[] = ["Пн", "Вт", "Ср", "Чт", "Пт"];

// ---------------------------------------------------------------------------
// Вспомогательный компонент: подсказка под полем
// ---------------------------------------------------------------------------

function FieldHelp({ id, text }: { id: string; text: string }) {
  return (
    <p id={id} className="text-sm text-muted-foreground mt-1">
      {text}
    </p>
  );
}

// ---------------------------------------------------------------------------
// Основной компонент
// ---------------------------------------------------------------------------

interface CompanySettingsPageProps {
  companyId: string;
  companyName: string;
}

export default function CompanySettingsPage({
  companyId,
  companyName,
}: CompanySettingsPageProps) {
  const { toast } = useToast();
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [showUnsavedDialog, setShowUnsavedDialog] = useState(false);

  const form = useForm<SettingsFormValues>({
    resolver: zodResolver(settingsSchema),
    defaultValues: {
      vat_mode: undefined,
      currency: undefined,
      timezone: "",
      workweek: DEFAULT_WORKWEEK,
      units: undefined,
      brand_color: "",
    },
  });

  const { isDirty, errors } = form.formState;

  // Симуляция загрузки настроек с бэкенда
  // В реальной реализации: GET /api/v1/companies/:id/settings
  useEffect(() => {
    const timer = setTimeout(() => {
      form.reset({
        vat_mode: "vat_20",
        currency: "RUB",
        timezone: "Europe/Moscow",
        workweek: DEFAULT_WORKWEEK,
        units: "metric",
        brand_color: "#1A73E8",
      });
      setIsLoading(false);
    }, 800);
    return () => clearTimeout(timer);
  }, [companyId, form]);

  // Блокировщик навигации при несохранённых изменениях (react-router-dom v6)
  const blocker = useBlocker(isDirty && !isSaving);

  useEffect(() => {
    if (blocker.state === "blocked") {
      setShowUnsavedDialog(true);
    }
  }, [blocker.state]);

  const onSubmit = async (data: SettingsFormValues) => {
    setIsSaving(true);
    try {
      // PATCH /api/v1/companies/:id/settings
      await new Promise((resolve) => setTimeout(resolve, 600)); // заглушка
      form.reset(data); // сбрасываем isDirty после успешного сохранения
      toast({ description: "Настройки компании сохранены" });
    } catch {
      toast({
        variant: "destructive",
        description: "Ошибка сохранения. Повторите попытку.",
      });
    } finally {
      setIsSaving(false);
    }
  };

  const handleCancel = () => {
    form.reset();
  };

  // ---------------------------------------------------------------------------
  // Состояние загрузки
  // ---------------------------------------------------------------------------

  if (isLoading) {
    return (
      <div className="p-6 space-y-6 max-w-2xl">
        <Skeleton className="h-5 w-32" />
        <Skeleton className="h-8 w-64" />
        {Array.from({ length: 7 }).map((_, i) => (
          <div key={i} className="space-y-2">
            <Skeleton className="h-4 w-40" />
            <Skeleton className="h-10 w-full" />
            <Skeleton className="h-3 w-72" />
          </div>
        ))}
      </div>
    );
  }

  // ---------------------------------------------------------------------------
  // Форма
  // ---------------------------------------------------------------------------

  return (
    <>
      {/* Диалог подтверждения ухода со страницы */}
      <AlertDialog
        open={showUnsavedDialog}
        onOpenChange={setShowUnsavedDialog}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Несохранённые изменения</AlertDialogTitle>
            <AlertDialogDescription>
              Есть несохранённые изменения. Покинуть страницу?
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel
              onClick={() => {
                setShowUnsavedDialog(false);
                blocker.reset?.();
              }}
            >
              Остаться
            </AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                setShowUnsavedDialog(false);
                blocker.proceed?.();
              }}
            >
              Покинуть
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <div className="p-6 max-w-2xl space-y-8">
        {/* Хлебная крошка */}
        <Link
          to={`/admin/companies/${companyId}`}
          className="text-sm text-muted-foreground hover:text-foreground flex items-center gap-1"
        >
          ← {companyName}
        </Link>

        <h1 className="text-2xl font-semibold">
          Настройки компании: {companyName}
        </h1>

        <form onSubmit={form.handleSubmit(onSubmit)} noValidate>
          {/* ── Секция: Бухгалтерия ─────────────────────────────────────── */}
          <section aria-labelledby="section-accounting" className="space-y-6">
            <div>
              <Separator className="my-2" />
              <h2
                id="section-accounting"
                className="text-sm font-medium text-muted-foreground uppercase tracking-wide mt-4 mb-4"
              >
                Бухгалтерия
              </h2>
            </div>

            {/* НДС-режим */}
            <div className="space-y-1">
              <Label htmlFor="vat_mode">
                НДС-режим <span aria-hidden>*</span>
              </Label>
              <Controller
                name="vat_mode"
                control={form.control}
                render={({ field }) => (
                  <Select
                    value={field.value}
                    onValueChange={field.onChange}
                  >
                    <SelectTrigger
                      id="vat_mode"
                      aria-required="true"
                      aria-describedby="vat_mode-help"
                      aria-invalid={!!errors.vat_mode}
                    >
                      <SelectValue placeholder="Выберите режим" />
                    </SelectTrigger>
                    <SelectContent>
                      {VAT_OPTIONS.map((o) => (
                        <SelectItem key={o.value} value={o.value}>
                          {o.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                )}
              />
              {errors.vat_mode && (
                <p className="text-sm text-destructive" role="alert">
                  {errors.vat_mode.message}
                </p>
              )}
              <FieldHelp
                id="vat_mode-help"
                text="Влияет на расчёт договоров и платежей"
              />
            </div>

            {/* Валюта */}
            <div className="space-y-1">
              <Label htmlFor="currency">
                Валюта <span aria-hidden>*</span>
              </Label>
              <Controller
                name="currency"
                control={form.control}
                render={({ field }) => (
                  <Select
                    value={field.value}
                    onValueChange={field.onChange}
                  >
                    <SelectTrigger
                      id="currency"
                      aria-required="true"
                      aria-describedby="currency-help"
                      aria-invalid={!!errors.currency}
                    >
                      <SelectValue placeholder="Выберите валюту" />
                    </SelectTrigger>
                    <SelectContent>
                      {CURRENCY_OPTIONS.map((o) => (
                        <SelectItem key={o.value} value={o.value}>
                          {o.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                )}
              />
              {errors.currency && (
                <p className="text-sm text-destructive" role="alert">
                  {errors.currency.message}
                </p>
              )}
              <FieldHelp
                id="currency-help"
                text="На M-OS-1 — справочно. Мультивалютный учёт — M-OS-2."
              />
            </div>
          </section>

          {/* ── Секция: Региональные настройки ─────────────────────────── */}
          <section
            aria-labelledby="section-regional"
            className="space-y-6 mt-8"
          >
            <div>
              <Separator className="my-2" />
              <h2
                id="section-regional"
                className="text-sm font-medium text-muted-foreground uppercase tracking-wide mt-4 mb-4"
              >
                Региональные настройки
              </h2>
            </div>

            {/* Часовой пояс */}
            <div className="space-y-1">
              <Label htmlFor="timezone">
                Часовой пояс <span aria-hidden>*</span>
              </Label>
              <Controller
                name="timezone"
                control={form.control}
                render={({ field }) => (
                  <Select
                    value={field.value}
                    onValueChange={field.onChange}
                  >
                    <SelectTrigger
                      id="timezone"
                      aria-required="true"
                      aria-describedby="timezone-help"
                      aria-invalid={!!errors.timezone}
                    >
                      <SelectValue placeholder="Выберите часовой пояс" />
                    </SelectTrigger>
                    <SelectContent>
                      {TIMEZONE_OPTIONS.map((o) => (
                        <SelectItem key={o.value} value={o.value}>
                          {o.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                )}
              />
              {errors.timezone && (
                <p className="text-sm text-destructive" role="alert">
                  {errors.timezone.message}
                </p>
              )}
              <FieldHelp
                id="timezone-help"
                text="Влияет на отображение времени в аудит-логе"
              />
            </div>

            {/* Рабочая неделя */}
            <div className="space-y-2">
              <Label
                id="workweek-label"
                className="block"
              >
                Рабочая неделя
              </Label>
              <Controller
                name="workweek"
                control={form.control}
                render={({ field }) => (
                  <div
                    role="group"
                    aria-labelledby="workweek-label"
                    aria-describedby="workweek-help"
                    className="flex flex-wrap gap-4"
                  >
                    {WEEKDAYS.map((day) => {
                      const checked = field.value.includes(day);
                      return (
                        <div key={day} className="flex items-center gap-2">
                          <Checkbox
                            id={`workweek-${day}`}
                            checked={checked}
                            onCheckedChange={(v) => {
                              if (v) {
                                field.onChange([...field.value, day]);
                              } else {
                                field.onChange(
                                  field.value.filter((d) => d !== day)
                                );
                              }
                            }}
                          />
                          <Label
                            htmlFor={`workweek-${day}`}
                            className="font-normal cursor-pointer"
                          >
                            {day}
                          </Label>
                        </div>
                      );
                    })}
                  </div>
                )}
              />
              {errors.workweek && (
                <p className="text-sm text-destructive" role="alert">
                  {errors.workweek.message}
                </p>
              )}
              <FieldHelp
                id="workweek-help"
                text="Влияет на расчёт сроков в BPM-процессах (M-OS-1.2)"
              />
            </div>

            {/* Единицы измерения */}
            <div className="space-y-1">
              <Label htmlFor="units">
                Единицы измерения <span aria-hidden>*</span>
              </Label>
              <Controller
                name="units"
                control={form.control}
                render={({ field }) => (
                  <Select
                    value={field.value}
                    onValueChange={field.onChange}
                  >
                    <SelectTrigger
                      id="units"
                      aria-required="true"
                      aria-describedby="units-help"
                      aria-invalid={!!errors.units}
                    >
                      <SelectValue placeholder="Выберите единицы" />
                    </SelectTrigger>
                    <SelectContent>
                      {UNITS_OPTIONS.map((o) => (
                        <SelectItem key={o.value} value={o.value}>
                          {o.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                )}
              />
              {errors.units && (
                <p className="text-sm text-destructive" role="alert">
                  {errors.units.message}
                </p>
              )}
              <FieldHelp
                id="units-help"
                text="Для строительных объёмов в отчётах"
              />
            </div>
          </section>

          {/* ── Секция: Внешний вид ─────────────────────────────────────── */}
          <section
            aria-labelledby="section-appearance"
            className="space-y-6 mt-8"
          >
            <div>
              <Separator className="my-2" />
              <h2
                id="section-appearance"
                className="text-sm font-medium text-muted-foreground uppercase tracking-wide mt-4 mb-4"
              >
                Внешний вид
              </h2>
            </div>

            {/* Логотип */}
            <div className="space-y-1">
              <Label>Логотип компании</Label>
              <div>
                <Button
                  type="button"
                  variant="outline"
                  disabled
                  aria-describedby="logo-help logo-notice"
                >
                  Загрузить PNG/SVG, до 2 МБ
                </Button>
              </div>
              <FieldHelp
                id="logo-help"
                text="Отображается в шапке при печати документов."
              />
              <Alert id="logo-notice" className="mt-2">
                <Info className="h-4 w-4" />
                <AlertDescription>
                  Загрузка файлов будет доступна в M-OS-2.
                </AlertDescription>
              </Alert>
            </div>

            {/* Цвет бренда */}
            <div className="space-y-1">
              <Label htmlFor="brand_color">Цвет бренда</Label>
              <div className="flex items-center gap-2">
                <span className="text-muted-foreground select-none">#</span>
                <Input
                  id="brand_color"
                  {...form.register("brand_color")}
                  placeholder="1A73E8"
                  maxLength={7}
                  aria-describedby="brand_color-help"
                  aria-invalid={!!errors.brand_color}
                  className="w-36 font-mono"
                />
                {/* Превью цвета */}
                <div
                  className="w-8 h-8 rounded border border-border flex-shrink-0"
                  style={{
                    backgroundColor: /^#[0-9A-Fa-f]{6}$/.test(
                      `#${form.watch("brand_color") ?? ""}`
                    )
                      ? `#${form.watch("brand_color")}`
                      : "transparent",
                  }}
                  aria-hidden
                  title="Превью цвета бренда"
                />
              </div>
              {errors.brand_color && (
                <p className="text-sm text-destructive" role="alert">
                  {errors.brand_color.message}
                </p>
              )}
              <FieldHelp
                id="brand_color-help"
                text="HEX-код. Пример: #1A73E8. Используется в шаблонах."
              />
            </div>
          </section>

          {/* ── Футер формы ─────────────────────────────────────────────── */}
          <div className="flex items-center justify-between mt-10 pt-6 border-t">
            <Button
              type="button"
              variant="outline"
              disabled={!isDirty || isSaving}
              onClick={handleCancel}
            >
              Отменить изменения
            </Button>
            <Button type="submit" disabled={isSaving}>
              {isSaving ? "Сохранение..." : "Сохранить"}
            </Button>
          </div>
        </form>

        {/* Ссылка на аудит-лог */}
        <div className="pt-2">
          <Separator />
          <Link
            to={`/admin/audit?entity_type=company_settings&entity_id=${companyId}`}
            className="text-sm text-muted-foreground hover:text-foreground mt-3 inline-block"
          >
            История изменений этих настроек →
          </Link>
        </div>
      </div>
    </>
  );
}
