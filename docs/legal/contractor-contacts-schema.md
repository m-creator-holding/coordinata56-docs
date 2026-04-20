# Схема ContactInfo для Contractor.contacts_json

**Дата:** 2026-04-19  
**Статус:** Draft — к ревью штатным юристом перед production-gate  
**Автор:** Legal adviser (субагент)

---

## Проблема

`Contractor.contacts_json` — поле JSONB без фиксированной схемы. Может содержать:
- ФИО контактных лиц (ст. 3 п. 1 152-ФЗ — персональные данные)
- Телефоны физических лиц
- Email адреса физических лиц
- Должности, прямо идентифицирующие физическое лицо

Freestyle JSONB без валидации означает, что:
1. Состав ПДн неизвестен оператору — нарушение ст. 18.1 152-ФЗ (документирование обработки)
2. Невозможно выполнить право на удаление (ст. 21 152-ФЗ) — непонятно, что именно удалять
3. Невозможно применить retention policy — непонятно, какое поле содержит ПДн

---

## Предлагаемая Pydantic-схема

```python
from pydantic import BaseModel, EmailStr, Field, field_validator
from typing import Optional
import re

class ContactPerson(BaseModel):
    """Контактное лицо подрядчика — ПДн физического лица.
    
    Обоснование: 152-ФЗ ст. 18.1 — оператор обязан фиксировать
    состав обрабатываемых ПДн. Схема делает состав явным.
    
    Цель обработки: взаимодействие с подрядчиком в рамках
    договора подряда (ГК РФ гл. 37), согласия физ. лица не требуется
    при наличии договора (152-ФЗ ст. 6 ч. 1 п. 5).
    """
    role: str = Field(
        ...,
        max_length=100,
        description="Роль в проекте: прораб | сметчик | директор | бухгалтер",
        examples=["прораб", "директор"],
    )
    name: Optional[str] = Field(
        None,
        max_length=200,
        description="ФИО или имя контактного лица — ПДн",
        examples=["Иванов Иван Иванович"],
    )
    phone: Optional[str] = Field(
        None,
        max_length=20,
        description="Телефон контактного лица — ПДн",
        examples=["+79001234567"],
    )
    email: Optional[EmailStr] = Field(
        None,
        description="Email контактного лица — ПДн",
    )
    telegram: Optional[str] = Field(
        None,
        max_length=64,
        description="Telegram username (без @). Не является ПДн само по себе, "
                    "но в связке с ФИО — может идентифицировать лицо.",
    )
    notes: Optional[str] = Field(
        None,
        max_length=500,
        description="Свободные заметки. НЕ вносить паспортные данные, "
                    "СНИЛС, ИНН физического лица.",
    )

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        pattern = re.compile(r"^\+7\d{10}$|^8\d{10}$|^\+[1-9]\d{6,14}$")
        if not pattern.match(v.replace(" ", "").replace("-", "")):
            raise ValueError(
                "Телефон должен быть в формате +7XXXXXXXXXX или 8XXXXXXXXXX"
            )
        return v

    @field_validator("notes")
    @classmethod
    def reject_sensitive_in_notes(cls, v: Optional[str]) -> Optional[str]:
        """Простейший guard: отклоняет notes с явными ПДн-паттернами.
        
        НЕ является полной защитой — только первый фильтр.
        Дополнить ML/regex scrubber в отдельной волне.
        """
        if v is None:
            return v
        sensitive_patterns = [
            r"\b\d{4}\s?\d{6}\b",           # серия+номер паспорта
            r"\b\d{3}-\d{3}-\d{3}\s?\d{2}\b",  # СНИЛС
            r"\b\d{10,12}\b",               # ИНН (10 или 12 цифр)
        ]
        for pattern in sensitive_patterns:
            if re.search(pattern, v):
                raise ValueError(
                    "Поле notes содержит паттерн паспортных данных/СНИЛС/ИНН. "
                    "Такие данные не могут храниться в Contractor.contacts_json. "
                    "Храните реквизиты только в зашифрованных ПДн-полях."
                )
        return v


class ContractorContacts(BaseModel):
    """Корневая схема для Contractor.contacts_json.
    
    Максимум 10 контактов на подрядчика — защита от аккумуляции ПДн.
    """
    contacts: list[ContactPerson] = Field(
        default_factory=list,
        max_length=10,
        description="Список контактных лиц подрядчика",
    )
    legal_basis: str = Field(
        default="contract",
        description="Правовое основание обработки ПДн: "
                    "contract (ГК гл. 37) | consent (152-ФЗ ст. 9)",
    )
```

---

## Валидация при INSERT/UPDATE

Backend-разработчику реализовать в сервисном слое (не в модели SQLAlchemy):

```python
# В ContractorService.create() и ContractorService.update()
from pydantic import ValidationError

def _validate_contacts(contacts_raw: dict | None) -> dict | None:
    """Валидация contacts_json перед записью в БД.
    
    Reject на ValidationError — HTTP 422 с деталями поля.
    """
    if contacts_raw is None:
        return None
    try:
        validated = ContractorContacts.model_validate(contacts_raw)
        return validated.model_dump()
    except ValidationError as exc:
        # Пробросить как HTTPException 422 с описанием нарушения схемы
        raise ValueError(f"contacts_json schema violation: {exc}") from exc
```

---

## SubagentEvent.payload — TODO для backend-dev

`SubagentEvent.payload` (JSONB) — мета-данные системных событий агентов.

**Текущая оценка:** преимущественно технические данные (event_type, timestamps, agent_id).  
**Риск:** при логировании BPM-событий payload может захватить ФИО пользователя (инициатор задачи), ID договора, суммы.

```python
# TODO: SubagentEvent.payload — legal review required
# При добавлении BPM-событий проверить: содержит ли payload ФИО / контакты /
# финансовые реквизиты физ. лиц? Если да — применить masking перед записью.
# Ответственный: backend-dev, Волна после MVP.
# Правовое основание: 152-ФЗ ст. 18.1, ПП РФ 1119 п. 15.
```

---

## Применимые нормы

| Норма | Содержание | Применение к схеме |
|---|---|---|
| 152-ФЗ ст. 3 п. 1 | ФИО, телефон, email = персональные данные | ContactPerson.name / phone / email |
| 152-ФЗ ст. 6 ч. 1 п. 5 | Обработка без согласия при наличии договора | legal_basis = "contract" |
| 152-ФЗ ст. 18.1 | Документирование состава ПДн | Фиксированная схема вместо JSONB freestyle |
| 152-ФЗ ст. 21 | Уничтожение ПДн при достижении цели | ContactPerson.* → удалять при закрытии договора |
| ПП РФ 1119 п. 15 | Меры защиты при обработке | notes-validator, max_length, rejection pattern |

---

## Открытые вопросы для штатного юриста

1. **Telegram-username:** является ли самостоятельным ПДн? Позиция РКН неоднозначна. Если да — требует согласия.
2. **legal_basis = "contract":** распространяется ли основание ст. 6 ч. 1 п. 5 на сотрудников подрядчика (не стороны договора)?  
   Если нет — требуется отдельное согласие по форме 152-ФЗ ст. 9.
3. **Передача данных подрядчику:** при показе contacts другим пользователям системы — нужна ли поручительская схема (ст. 6 ч. 3 152-ФЗ)?

**Здесь нужен штатный юрист** для п. 2 — это может изменить правовое основание обработки.
