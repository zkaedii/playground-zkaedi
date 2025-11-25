# DeFi Portfolio Tracker

A full-stack application for tracking DeFi portfolios, transactions, and analytics.

## Architecture

```
fullstack-app/
├── backend/                 # Express.js API server
│   ├── src/
│   │   ├── db/             # SQLite database layer
│   │   ├── middleware/     # Auth & validation middleware
│   │   ├── routes/         # API route handlers
│   │   ├── services/       # Business logic
│   │   └── types/          # TypeScript types
│   └── package.json
│
├── frontend/               # React + Vite frontend
│   ├── src/
│   │   ├── components/     # React components
│   │   ├── services/       # API client
│   │   ├── store/          # Zustand state management
│   │   └── types/          # TypeScript types
│   └── package.json
│
└── README.md
```

## Features

### Backend
- **Express.js** REST API with TypeScript
- **SQLite** database with better-sqlite3
- **JWT** authentication with refresh tokens
- **Zod** request validation
- **Rate limiting** and security headers (Helmet)
- **CORS** configuration

### Frontend
- **React 19** with Vite
- **TypeScript** for type safety
- **TanStack Query** for data fetching
- **Zustand** for state management
- **React Router** for navigation
- **Tailwind CSS** for styling
- **Framer Motion** for animations
- **Recharts** for data visualization

### API Endpoints

#### Authentication
- `POST /api/auth/register` - Register new user
- `POST /api/auth/login` - Login user
- `POST /api/auth/refresh` - Refresh access token
- `POST /api/auth/logout` - Logout user
- `GET /api/auth/me` - Get current user
- `PATCH /api/auth/profile` - Update profile
- `POST /api/auth/change-password` - Change password

#### Portfolios
- `GET /api/portfolios` - List portfolios
- `GET /api/portfolios/:id` - Get portfolio with assets
- `POST /api/portfolios` - Create portfolio
- `PATCH /api/portfolios/:id` - Update portfolio
- `DELETE /api/portfolios/:id` - Delete portfolio
- `POST /api/portfolios/:id/default` - Set default portfolio

#### Assets
- `GET /api/portfolios/:id/assets` - List assets
- `POST /api/portfolios/:id/assets` - Add asset
- `PATCH /api/portfolios/:portfolioId/assets/:assetId` - Update balance
- `DELETE /api/portfolios/:portfolioId/assets/:assetId` - Remove asset

#### Transactions
- `GET /api/transactions` - List transactions (paginated)
- `POST /api/transactions` - Record transaction
- `GET /api/transactions/recent` - Get recent transactions
- `GET /api/transactions/by-portfolio/:id` - Filter by portfolio
- `GET /api/transactions/by-type/:type` - Filter by type
- `GET /api/transactions/by-chain/:chainId` - Filter by chain

#### Watchlist
- `GET /api/portfolios/watchlist/items` - Get watchlist
- `POST /api/portfolios/watchlist/items` - Add to watchlist
- `PATCH /api/portfolios/watchlist/items/:id` - Update item
- `DELETE /api/portfolios/watchlist/items/:id` - Remove item

#### Analytics
- `GET /api/analytics/portfolio/:id` - Portfolio analytics
- `GET /api/analytics/user` - User analytics
- `GET /api/analytics/transactions` - Transaction stats
- `GET /api/analytics/summary` - Dashboard summary
- `GET /api/analytics/leaderboard` - Public leaderboard
- `POST /api/analytics/snapshot/:id` - Create snapshot

## Getting Started

### Prerequisites
- Node.js 20+
- npm or yarn

### Backend Setup

```bash
cd fullstack-app/backend

# Install dependencies
npm install

# Copy environment file
cp .env.example .env

# Start development server
npm run dev
```

The API will be available at `http://localhost:3001`

### Frontend Setup

```bash
cd fullstack-app/frontend

# Install dependencies
npm install

# Start development server
npm run dev
```

The frontend will be available at `http://localhost:5173`

### Environment Variables

#### Backend (.env)
```
PORT=3001
NODE_ENV=development
JWT_SECRET=your-super-secret-jwt-key
JWT_EXPIRES_IN=24h
DATABASE_PATH=./data/portfolio.db
CORS_ORIGIN=http://localhost:5173
```

#### Frontend (.env)
```
VITE_API_URL=/api
```

## Tech Stack

### Backend
| Technology | Purpose |
|-----------|---------|
| Express.js | Web framework |
| TypeScript | Type safety |
| better-sqlite3 | SQLite database |
| bcryptjs | Password hashing |
| jsonwebtoken | JWT auth |
| Zod | Validation |
| Helmet | Security headers |
| Morgan | Request logging |

### Frontend
| Technology | Purpose |
|-----------|---------|
| React 19 | UI library |
| Vite | Build tool |
| TypeScript | Type safety |
| TanStack Query | Data fetching |
| Zustand | State management |
| React Router | Routing |
| Tailwind CSS | Styling |
| Framer Motion | Animations |
| Recharts | Charts |
| React Hook Form | Forms |
| Axios | HTTP client |

## Supported Chains

- Arbitrum One (42161)
- Arbitrum Sepolia (421614)
- Ethereum Mainnet (1)

## Database Schema

### Tables
- `users` - User accounts
- `portfolios` - User portfolios
- `assets` - Portfolio assets
- `transactions` - Transaction history
- `watchlist` - Token watchlist
- `portfolio_snapshots` - Historical snapshots
- `notifications` - User notifications
- `sessions` - Refresh token sessions

## Scripts

### Backend
```bash
npm run dev          # Start development server
npm run build        # Build for production
npm run start        # Start production server
npm run test         # Run tests
npm run db:migrate   # Run migrations
```

### Frontend
```bash
npm run dev          # Start development server
npm run build        # Build for production
npm run preview      # Preview production build
npm run lint         # Run ESLint
```

## Security Features

- Password hashing with bcrypt (12 rounds)
- JWT authentication with refresh tokens
- Rate limiting (100 req/15min, 10 auth attempts/15min)
- Security headers with Helmet
- CORS protection
- Input validation with Zod
- SQL injection prevention (parameterized queries)

## License

MIT
