import React, { useEffect, useState } from 'react';

interface ParkedBillsBadgeProps {
  count: number;
  className?: string;
}

export const ParkedBillsBadge: React.FC<ParkedBillsBadgeProps> = ({ count, className = '' }) => {
  const [isAnimating, setIsAnimating] = useState(false);
  const [prevCount, setPrevCount] = useState(count);

  useEffect(() => {
    if (count !== prevCount) {
      setIsAnimating(true);
      setPrevCount(count);
      
      const timer = setTimeout(() => {
        setIsAnimating(false);
      }, 600);
      
      return () => clearTimeout(timer);
    }
  }, [count, prevCount]);

  if (count === 0) return null;

  const displayCount = count > 99 ? '99+' : count.toString();

  return (
    <>
      <span
        className={`
          absolute -top-2 -right-2 min-w-[20px] h-5 px-1.5 
          bg-red-500 text-white text-xs font-bold rounded-full 
          flex items-center justify-center
          ${isAnimating ? 'animate-bounce' : ''}
          ${className}
        `}
        aria-live="polite"
        aria-label={`${count} parked bills`}
      >
        {displayCount}
      </span>
      {isAnimating && (
        <div
          className="sr-only"
          aria-live="polite"
          aria-atomic="true"
        >
          Parked bills updated: {count}
        </div>
      )}
    </>
  );
};