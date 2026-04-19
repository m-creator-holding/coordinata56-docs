# Промпт для v0.dev — Company Settings

## Инструкция по использованию

Открыть https://v0.dev, нажать «Generate», вставить промпт ниже как есть.
Стек: React 18 + TypeScript, Tailwind CSS v3.4, shadcn/ui (встроен в v0.dev по умолчанию).

---

## Промпт (copy-paste в v0.dev)

```
Create a Company Settings page for an internal B2B admin panel.

Stack: React 18, TypeScript, Tailwind CSS v3.4, shadcn/ui components only.
No external component libraries. No color picker libraries.

Layout:
- Left sidebar (fixed width ~240px) with navigation groups:
  - "Управление": Юрлица, Пользователи, Роли
  - "Права и настройки": Матрица прав, Настройки компании (active)
  - "Система": Интеграции, Системная конфигурация
- Top breadcrumb: "← ООО «Металл»" link back to company card
- Main content area: page title "Настройки компании: ООО «Металл»"

Form sections (use shadcn Card or section dividers):

Section 1 — "Бухгалтерия":
1. НДС-режим (required Select): options "Без НДС", "НДС 20%", "НДС 10%", "УСН". Help text: "Влияет на расчёт договоров и платежей"
2. Валюта (required Select): options "RUB", "USD", "EUR". Help text: "На M-OS-1 — справочно. Мультивалютный учёт — M-OS-2."

Section 2 — "Региональные настройки":
3. Часовой пояс (required Select): options "Europe/Moscow (UTC+3)", "Europe/Kaliningrad (UTC+2)", "Asia/Yekaterinburg (UTC+5)", "Asia/Novosibirsk (UTC+7)". Help text: "Влияет на отображение времени в аудит-логе"
4. Рабочая неделя (Checkbox group, 7 checkboxes for Mon–Sun, labels in Russian "Пн Вт Ср Чт Пт Сб Вс", Mon–Fri checked by default). Help text: "Влияет на расчёт сроков в BPM-процессах"
5. Единицы измерения (required Select): options "Метрические (м, кг, м²)", "Имперские". Help text: "Для строительных объёмов в отчётах"

Section 3 — "Внешний вид":
6. Логотип компании: disabled Button "Загрузить PNG/SVG, до 2 МБ" with an info Alert below: "Загрузка файлов будет доступна в M-OS-2." Help text: "Отображается в шапке при печати документов."
7. Цвет бренда: text Input with "#" prefix placeholder "1A73E8", and a small color preview square (div with backgroundColor set to the input value). Help text: "HEX-код. Пример: #1A73E8. Используется в шаблонах."

Footer:
- Two buttons: "Отменить изменения" (outline variant) and "Сохранить" (default variant, right-aligned)
- Below form: link "История изменений этих настроек →"

States to handle:
- isLoading: show Skeleton components instead of form fields
- isDirty: enable "Отменить изменения" button only when form has unsaved changes; disable it otherwise
- onSave success: show shadcn Toast "Настройки компании сохранены"
- onSave error: show shadcn Toast with error message, keep form data
- beforeunload guard: if isDirty, show shadcn AlertDialog "Есть несохранённые изменения. Покинуть страницу?"

Accessibility:
- All form fields: htmlFor + id pairs
- Required fields: aria-required="true"
- Help texts: aria-describedby linking field to help text
- Sidebar nav items: aria-current="page" for active item

Use react-hook-form with zod schema for validation.
Export as default CompanySettingsPage component.
```

---

## Примечания по безопасности

- Промпт не содержит реальных ИНН, ФИО, email, токенов или секретов
- Названия компании («ООО «Металл»») — вымышленные, не привязаны к реальным юрлицам холдинга
- Промпт уходит на серверы Vercel — это задокументировано в experiment-report.md
