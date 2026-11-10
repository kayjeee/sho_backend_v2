# School Shop Backend Documentation

## Overview

The School Shop backend enables parents to browse a school's catalog of printed materials (e.g., past exam papers, assignments), stationery, and uniforms, add items to a cart, and place collection orders for school fulfilment. School administrators manage the catalog items and progress orders through an allowed lifecycle workflow.

---

## Data Models

### 1. `CatalogItem`
Represents an item available in a school's shop.
- **Collection**: `catalog_items`
- **Associations**:
  - `belongs_to :school` (`class_name: 'School'`, `foreign_key: :school_id`)
  - `embeds_many :variants` (`class_name: 'CatalogVariant'`)
- **Fields**:
  - `name` (String, required): Item display name.
  - `description` (String): Detailed description.
  - `category` (String, required): Enum `print`, `stationery`, `uniform`.
  - `subcategory` (String): Free text, e.g., `past_exam_paper`, `assignment`, `pens`, `blazer`.
  - `price_cents` (Integer, required): Base price in integer cents (e.g. 2500 = R25.00).
  - `currency` (String, default: "ZAR"): Currency code.
  - `image_url` (String): Product image URL.
  - `is_active` (Boolean, default: true): Whether item is displayed/purchasable. Soft-delete sets this to false.
  - `stock_quantity` (Integer, nullable): Available inventory. `nil` denotes unlimited stock.
  - `grade_ids` (Array of Strings): Grades eligible for this item. An empty array `[]` denotes availability to all grades.
  - `subject` (String): Academic subject (if applicable).
  - `academic_year` (String): Academic year (if applicable).
  - `tags` (Array of Strings): Search/filter tags.
  - `position` (Integer, default: 0): Custom display ordering.
  - `print_options` (Hash): Configuration for print jobs (`color_allowed`, `double_sided_allowed`, `max_copies`).
  - `file_url` (String): File/document URL for print jobs.
- **Indexes**:
  - `{ school_id: 1, category: 1, is_active: 1 }`
  - `{ school_id: 1, is_active: 1 }`

### 2. `CatalogVariant` (Embedded in `CatalogItem`)
Represents variations such as size, color, or bundle packaging.
- **Fields**:
  - `label` (String, required): Variant label (e.g., `"S"`, `"M"`, `"L"`).
  - `price_cents` (Integer, optional): Price override in integer cents. When `nil`, falls back to parent item `price_cents`.
  - `stock_quantity` (Integer, optional): Variant inventory. `nil` denotes unlimited stock.

### 3. `Order`
Represents a parent's request/order for shop items.
- **Collection**: `orders`
- **Associations**:
  - `belongs_to :school` (`class_name: 'School'`, `foreign_key: :school_id`)
  - `belongs_to :user` (`class_name: 'User'`, `foreign_key: :user_id`)
  - `embeds_many :items` (`class_name: 'OrderItem'`)
- **Fields**:
  - `order_number` (String, unique): Human-readable order code (e.g., `SHO-YYMMDD-XXXX`).
  - `learner_id` (String, optional): Associated learner ID.
  - `status` (String, default: `"placed"`): One of `placed`, `accepted`, `preparing`, `ready`, `completed`, `cancelled`, `rejected`.
  - `fulfilment_method` (String, default: `"collect"`): Pickup at school.
  - `notes` (String): Notes from parent.
  - `subtotal_cents` (Integer): Server-calculated order subtotal in integer cents.
  - `currency` (String, default: `"ZAR"`).
  - `payment_status` (String, default: `"unpaid"`): Payment integration is out of scope for this release.
  - `status_history` (Array of Hashes): `[{ status, at, by }]`.
  - `placed_at` (DateTime): Timestamp when order was placed.
- **Indexes**:
  - `{ school_id: 1, status: 1, created_at: -1 }`
  - `{ user_id: 1, created_at: -1 }`
  - `{ order_number: 1 }` (unique)

### 4. `OrderItem` (Embedded in `Order`)
Snapshot of item details at the moment of order placement.
- **Fields**:
  - `catalog_item_id` (String, required)
  - `name_snapshot` (String, required)
  - `category_snapshot` (String)
  - `unit_price_cents` (Integer, required)
  - `quantity` (Integer, required, > 0)
  - `variant_label` (String, optional)
  - `options` (Hash): Print choices (e.g., `{ color: true, double_sided: true, copies: 1 }`).

---

## Status Transition Lifecycle

Orders follow a strict state machine:
```
placed ---> accepted ---> preparing ---> ready ---> completed
  |            |
  +-> rejected +-> cancelled
  |
  +-> cancelled
```
- Allowed transitions:
  - `placed` -> `accepted`, `rejected`, `cancelled`
  - `accepted` -> `preparing`, `cancelled`
  - `preparing` -> `ready`
  - `ready` -> `completed`
  - `completed`, `cancelled`, `rejected` are terminal states (no transitions permitted).
- **Parent cancellation rules**: A parent may only cancel an order if it is in `placed` status.
- **Stock restoration**: When an order transitions to `cancelled` or `rejected`, all reserved item and variant stock is atomically restored.

---

## Monetary Values & Pricing

- **All money is strictly stored as integer cents** (`price_cents`, `subtotal_cents`, `unit_price_cents`). No floats are used in monetary fields to avoid floating point precision errors.
- **Server-side price verification**: Any unit prices sent by the client in `POST /api/v1/orders` are discarded. The server recalculates prices directly from current `CatalogItem` / `CatalogVariant` definitions.

---

## API Endpoints & Request / Response Contracts

### Parent Endpoints

#### 1. List School Catalog Items
- **Route**: `GET /api/v1/schools/:school_id/catalog_items`
- **Query Params**:
  - `auth0_id` (string, optional)
  - `category` (string, optional: `print` | `stationery` | `uniform`)
  - `grade_id` (string, optional: filters items matching this grade or available to all)
  - `only_in_stock` (boolean, optional: `true`)
  - `q` (string, optional: search query across name, description, tags, etc.)
- **Response `200 OK`**:
```json
{
  "success": true,
  "total": 1,
  "data": [
    {
      "id": "664fa1e2b5821c0012ab1234",
      "school_id": "664fa0b1b5821c0012ab1230",
      "name": "Grade 11 Mathematics Past Paper 2024",
      "description": "Complete past exam paper with memorandum",
      "category": "print",
      "subcategory": "past_exam_paper",
      "price_cents": 2500,
      "currency": "ZAR",
      "image_url": "https://example.com/item.png",
      "is_active": true,
      "stock_quantity": 40,
      "in_stock": true,
      "grade_ids": ["664fa0b1b5821c0012ab1239"],
      "subject": "Mathematics",
      "academic_year": "2024",
      "tags": ["math", "exam", "paper"],
      "position": 1,
      "print_options": {
        "color_allowed": false,
        "double_sided_allowed": true,
        "max_copies": 2
      },
      "file_url": "https://example.com/paper.pdf",
      "variants": [],
      "created_at": "2026-07-24T10:00:00.000Z",
      "updated_at": "2026-07-24T10:00:00.000Z"
    }
  ]
}
```

#### 2. Get Single Catalog Item
- **Route**: `GET /api/v1/catalog_items/:id`
- **Response `200 OK`**:
```json
{
  "success": true,
  "data": {
    "id": "664fa1e2b5821c0012ab1234",
    "school_id": "664fa0b1b5821c0012ab1230",
    "name": "School Blazer",
    "description": "Official school uniform blazer",
    "category": "uniform",
    "subcategory": "blazer",
    "price_cents": 65000,
    "currency": "ZAR",
    "image_url": null,
    "is_active": true,
    "stock_quantity": null,
    "in_stock": true,
    "grade_ids": [],
    "subject": null,
    "academic_year": null,
    "tags": ["uniform", "blazer"],
    "position": 0,
    "print_options": {},
    "file_url": null,
    "variants": [
      {
        "id": "664fa1e2b5821c0012ab1235",
        "label": "M",
        "price_cents": 65000,
        "stock_quantity": 12,
        "in_stock": true
      }
    ],
    "created_at": "2026-07-24T10:00:00.000Z",
    "updated_at": "2026-07-24T10:00:00.000Z"
  }
}
```

#### 3. Create Order
- **Route**: `POST /api/v1/orders`
- **Request Body**:
```json
{
  "auth0_id": "auth0|parent_123",
  "school_id": "664fa0b1b5821c0012ab1230",
  "learner_id": "664fa0b1b5821c0012ab1244",
  "notes": "Please package neatly for collection",
  "items": [
    {
      "catalog_item_id": "664fa1e2b5821c0012ab1234",
      "variant_label": "M",
      "quantity": 1,
      "options": {
        "color": false,
        "double_sided": true
      }
    }
  ]
}
```
- **Response `201 Created`**:
```json
{
  "success": true,
  "message": "Order placed successfully",
  "data": {
    "id": "664fa301b5821c0012ab1299",
    "order_number": "SHO-260724-4X7K",
    "school_id": "664fa0b1b5821c0012ab1230",
    "user_id": "664fa0b1b5821c0012ab1201",
    "learner_id": "664fa0b1b5821c0012ab1244",
    "status": "placed",
    "fulfilment_method": "collect",
    "notes": "Please package neatly for collection",
    "subtotal_cents": 65000,
    "currency": "ZAR",
    "payment_status": "unpaid",
    "placed_at": "2026-07-24T11:00:00.000Z",
    "status_history": [
      {
        "status": "placed",
        "at": "2026-07-24T11:00:00.000Z",
        "by": "664fa0b1b5821c0012ab1201"
      }
    ],
    "items": [
      {
        "id": "664fa301b5821c0012ab129a",
        "catalog_item_id": "664fa1e2b5821c0012ab1234",
        "name": "School Blazer",
        "category": "uniform",
        "unit_price_cents": 65000,
        "quantity": 1,
        "variant_label": "M",
        "options": {
          "color": false,
          "double_sided": true
        },
        "total_price_cents": 65000
      }
    ],
    "created_at": "2026-07-24T11:00:00.000Z",
    "updated_at": "2026-07-24T11:00:00.000Z"
  }
}
```

#### 4. List Parent Orders
- **Route**: `GET /api/v1/orders?auth0_id=auth0|parent_123`
- **Query Params**:
  - `auth0_id` (string, required)
  - `school_id` (string, optional)
  - `status` (string, optional)
- **Response `200 OK`**:
```json
{
  "success": true,
  "total": 1,
  "data": [ ... ]
}
```

#### 5. Get Single Order
- **Route**: `GET /api/v1/orders/:id?auth0_id=auth0|parent_123`
- **Response `200 OK`**:
```json
{
  "success": true,
  "data": { ... }
}
```

#### 6. Cancel Order (Parent)
- **Route**: `POST /api/v1/orders/:id/cancel`
- **Request Body**: `{ "auth0_id": "auth0|parent_123" }`
- **Response `200 OK`**:
```json
{
  "success": true,
  "message": "Order cancelled successfully",
  "data": {
    "id": "664fa301b5821c0012ab1299",
    "status": "cancelled",
    ...
  }
}
```

---

### School Admin Endpoints

Admin authorization is verified using `UserSchoolRole` with `role: "Admin"` for the target school.

#### 1. Create Catalog Item
- **Route**: `POST /api/v1/schools/:school_id/catalog_items`
- **Request Body**:
```json
{
  "auth0_id": "auth0|admin_123",
  "catalog_item": {
    "name": "A4 Exercise Book 72pg",
    "description": "Feint and margin",
    "category": "stationery",
    "subcategory": "notebook",
    "price_cents": 1500,
    "stock_quantity": 100,
    "grade_ids": [],
    "variants": []
  }
}
```
- **Response `201 Created`**:
```json
{
  "success": true,
  "message": "Catalog item created successfully",
  "data": { ... }
}
```

#### 2. Update Catalog Item
- **Route**: `PATCH /api/v1/catalog_items/:id`
- **Request Body**:
```json
{
  "auth0_id": "auth0|admin_123",
  "catalog_item": {
    "price_cents": 1600,
    "stock_quantity": 90
  }
}
```
- **Response `200 OK`**:
```json
{
  "success": true,
  "message": "Catalog item updated successfully",
  "data": { ... }
}
```

#### 3. Soft-Delete Catalog Item
- **Route**: `DELETE /api/v1/catalog_items/:id?auth0_id=auth0|admin_123`
- **Response `200 OK`**:
```json
{
  "success": true,
  "message": "Catalog item deactivated successfully",
  "data": {
    "id": "...",
    "is_active": false,
    ...
  }
}
```

#### 4. List School Orders (Admin)
- **Route**: `GET /api/v1/schools/:school_id/orders?auth0_id=auth0|admin_123`
- **Query Params**:
  - `auth0_id` (string, required)
  - `status` (string, optional: `placed`, `accepted`, `preparing`, etc.)
  - `learner_id` (string, optional)
  - `start_date` (ISO date string, optional)
  - `end_date` (ISO date string, optional)
- **Response `200 OK`**:
```json
{
  "success": true,
  "total": 5,
  "data": [ ... ]
}
```

#### 5. Update Order Status (Admin)
- **Route**: `PATCH /api/v1/orders/:id/status`
- **Request Body**:
```json
{
  "auth0_id": "auth0|admin_123",
  "status": "accepted"
}
```
- **Response `200 OK`**:
```json
{
  "success": true,
  "message": "Order status updated to accepted",
  "data": {
    "id": "...",
    "status": "accepted",
    ...
  }
}
```

---

## Out of Scope & Future Work
- Direct online payment gateways (e.g. PayFast, Stripe). Currently `payment_status` defaults to `unpaid`.
- Delivery tracking and shipping logistics (only `"collect"` pickup at school is supported this round).
- Automated SMS / WhatsApp / email push notifications on order status transitions.
