# Database Design Specification
## Hybrid Marketplace Mobile Application

---

# 1. Overview

This section describes the database design for the Hybrid Marketplace Mobile Application.  
The system uses a **relational database structure (Supabase/PostgreSQL)** as the primary data storage.

The design supports:
- Hybrid transactions (sell and trade)
- User-to-user communication
- Structured transaction management
- Scalable and normalized data relationships

---

# 2. Core Tables

The system consists of five main entities:

- Users
- Items
- Transaction Requests
- Chats
- Messages

---

# 3. Table Design

---

## 3.1 Users Table

### Description
Stores user account and profile information.

### Attributes

| Attribute        | Type        | Description |
|-----------------|------------|-------------|
| id              | UUID (PK)  | Unique user identifier (from Supabase Auth) |
| username        | TEXT       | User display name |
| email           | TEXT       | User email address |
| profile_image   | TEXT       | URL of profile picture |
| created_at      | TIMESTAMP  | Account creation time |

### Notes
- Authentication is handled by Supabase Auth.
- No password is stored in this table.

---

## 3.2 Items Table

### Description
Stores all item listings created by users.

### Attributes

| Attribute        | Type        | Description |
|-----------------|------------|-------------|
| id              | UUID (PK)  | Unique item identifier |
| title           | TEXT       | Item title |
| description     | TEXT       | Item description |
| price           | DECIMAL    | Selling price (nullable) |
| listing_type    | TEXT       | 'sell', 'trade', or 'both' |
| owner_id        | UUID (FK)  | References users.id |
| status          | TEXT       | 'available' or 'completed' |
| category        | TEXT       | Item category |
| image_url       | TEXT       | Item image URL |
| condition       | TEXT       | 'new' or 'used' |
| created_at      | TIMESTAMP  | Listing creation time |

### Notes
- `price` is nullable for trade-only items.
- `listing_type` defines transaction flexibility.

---

## 3.3 Transaction Requests Table

### Description
Handles both purchase and trade requests using a unified structure.

### Attributes

| Attribute         | Type        | Description |
|------------------|------------|-------------|
| id               | UUID (PK)  | Unique request identifier |
| item_id          | UUID (FK)  | Target item (requested item) |
| requester_id     | UUID (FK)  | User who sends the request |
| type             | TEXT       | 'purchase' or 'trade' |
| offered_price    | DECIMAL    | Offered price (nullable) |
| offered_item_id  | UUID (FK)  | Offered item for trade (nullable) |
| status           | TEXT       | 'pending', 'accepted', 'rejected', 'cancelled' |
| created_at       | TIMESTAMP  | Request creation time |

### Business Rules

- If `type = 'purchase'`:
  - `offered_price` MUST NOT be NULL
  - `offered_item_id` MUST be NULL

- If `type = 'trade'`:
  - `offered_item_id` MUST NOT be NULL
  - `offered_price` MUST be NULL

### Notes
- This design avoids duplication by merging purchase and trade logic into a single table.
- Supports scalable transaction handling.

---

## 3.4 Chats Table

### Description
Represents a conversation between two users.

### Attributes

| Attribute      | Type        | Description |
|---------------|------------|-------------|
| id            | UUID (PK)  | Unique chat identifier |
| user1_id      | UUID (FK)  | First participant |
| user2_id      | UUID (FK)  | Second participant |
| item_id       | UUID (FK)  | Related item (required) |
| last_message  | TEXT       | Last message preview |
| updated_at    | TIMESTAMP  | Last activity time |

### Notes
- One chat is created per user pair per item.
- Item link is required.

---

## 3.5 Messages Table

### Description
Stores individual messages within a chat.

### Attributes

| Attribute    | Type        | Description |
|-------------|------------|-------------|
| id          | UUID (PK)  | Unique message identifier |
| chat_id     | UUID (FK)  | References chats.id |
| sender_id   | UUID (FK)  | Message sender |
| content     | TEXT       | Message content |
| read_at     | TIMESTAMP  | Read timestamp (NULL = unread) |
| edited_at   | TIMESTAMP  | Last edit timestamp |
| deleted_at  | TIMESTAMP  | Soft-delete timestamp |
| deleted_by  | UUID (FK)  | User who deleted the message |
| created_at  | TIMESTAMP  | Message timestamp |

### Notes
- Each chat can have multiple messages (1-to-many relationship).
- Sender can edit their own message within 3 minutes.
- Sender can delete only within 3 minutes; both users see "<username> deleted a msg".

---

# 4. Entity Relationships

The system follows a normalized relational structure:

- One User → Many Items  
- One Item → Many Transaction Requests  
- One User → Many Transaction Requests  
- One Chat → Many Messages  
- Users ↔ Users → Chat (many-to-many via chats table)

---

# 5. Design Justification

The database design follows key principles:

### Normalization
- Eliminates redundancy
- Ensures data consistency

### Scalability
- Supports large number of users and transactions

### Flexibility
- Unified transaction request model supports both buying and trading

### Maintainability
- Clear separation of entities simplifies future enhancements

---

# 6. Conclusion

This database design provides a structured and scalable foundation for the hybrid marketplace system.  
By integrating transaction flexibility, communication features, and normalized relationships, the system ensures efficient data management and supports real-world application requirements.